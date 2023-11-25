# Copyright 2023 Google LLC.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# [START serviceextensions_callout_add_header]
"""
# Example external processing server
----
This server does two things:
* When it receives a `request_headers`, it replaces the Host header
        with "host: service-extensions.com" and resets the path to /

This server also has optional SSL authentication.
"""
# [START serviceextensions_callout_add_header_imports]
from concurrent import futures
from http.server import BaseHTTPRequestHandler, HTTPServer

from typing import Iterator, List, Tuple

import grpc

from grpc import ServicerContext

import service_pb2
import service_pb2_grpc

# Used to validate IAP JWT tokens
from google.auth.transport import requests
from google.oauth2 import id_token

# Used to validate IPv4 addresses
from ipaddress import ip_network, ip_address

from os import environ

# Backend services on GCE VMs, GKE and hybrid use this port.
EXT_PROC_SECURE_PORT = 8443
# Backend services on Cloud Run use this port.
EXT_PROC_INSECURE_PORT = 8080
# Cloud health checks use this port.
HEALTH_CHECK_PORT = 8000
# Example SSL Credentials for gRPC server
# PEM-encoded private key & PEM-encoded certificate chain
SERVER_CERTIFICATE = open("ssl_creds/localhost.crt", "rb").read()
SERVER_CERTIFICATE_KEY = open("ssl_creds/localhost.key", "rb").read()
ROOT_CERTIFICATE = open("ssl_creds/root.crt", "rb").read()


# [END serviceextensions_callout_add_header_imports]
# [START serviceextensions_callout_add_header_main]
def add_headers_mutation(
    headers: List[Tuple[str, str]], clear_route_cache: bool = False
) -> service_pb2.HeadersResponse:
    """
    Returns an ext_proc HeadersResponse for adding a list of headers.
    clear_route_cache should be set to influence service selection for route
    extensions.
    """
    response_header_mutation = service_pb2.HeadersResponse()
    response_header_mutation.response.header_mutation.set_headers.extend(
        [
            service_pb2.HeaderValueOption(
                header=service_pb2.HeaderValue(key=k, raw_value=bytes(v, "utf-8"))
            )
            for k, v in headers
        ]
    )
    if clear_route_cache:
        response_header_mutation.response.clear_route_cache = True
    return response_header_mutation


def validate_iap_jwt(iap_jwt, expected_audience):
    """Validate an IAP JWT.

    Args:
      iap_jwt: The contents of the X-Goog-IAP-JWT-Assertion header.
      expected_audience: The Signed Header JWT audience. See
          https://cloud.google.com/iap/docs/signed-headers-howto
          for details on how to get this value.

    Returns:
      (user_id, user_email, error_str).
    """

    try:
        decoded_jwt = id_token.verify_token(
            iap_jwt,
            requests.Request(),
            audience=expected_audience,
            certs_url="https://www.gstatic.com/iap/verify/public_key",
        )
        return (decoded_jwt["sub"], decoded_jwt["email"], "")
    except Exception as e:
        return (None, None, f"**ERROR: JWT validation error {e}**")


def custom_response(status_code, custom_response):
    immediate_response = service_pb2.ImmediateResponse(
        status=service_pb2.HttpStatus(code=status_code), body=custom_response
    )
    yield service_pb2.ProcessingResponse(immediate_response=immediate_response)


def handle_iap_jwt_validation(header_value):
    print(f"\tHeader value is => {header_value}")
    ser_id, user_email, error_str = validate_iap_jwt(header_value, "")
    if error_str:
        print(f"\t\tINVALID JWT ==> {error_str}")
        return custom_response(
            service_pb2.StatusCode.Unauthorized,
            "Either the JWT token is invalid or was not provided",
        )
    return None  # Return None if no error


def handle_xff_validation(header_value):
    print(f"\tHeader value is => {header_value}")
    ip_list = header_value.split(",")
    allow_request = True
    deny_request = False
    if len(ip_list) >= 2:
        source_ip = ip_list[-2]
        if environ.get("se_allowed_sources"):
            allow_request = False
            allowed_sources = environ.get("se_allowed_sources").split(",")
            for allowed_source in allowed_sources:
                if ip_address(source_ip) in ip_network(allowed_source):
                    return None
        if environ.get("se_denied_sources"):
            denied_sources = environ.get("se_denied_sources").split(",")
            for denied_source in denied_sources:
                if ip_address(source_ip) in ip_network(denied_source):
                    deny_request = True
        if not allow_request:
            return custom_response(
                service_pb2.StatusCode.Forbidden,
                f"Requests for source ip ({source_ip}) was not allowed",
            )
        if deny_request:
            return custom_response(
                service_pb2.StatusCode.Forbidden,
                f"Requests for source ip ({source_ip}) was denied",
            )


scoped_header_actions = {
    "x-goog-iap-jwt-assertion-test": handle_iap_jwt_validation,
    "x-goog-iap-jwt-assertion": handle_iap_jwt_validation,
    "x-forwarded-for-test": handle_xff_validation,
    "x-forwarded-for": handle_xff_validation,
}


class CalloutProcessor(service_pb2_grpc.ExternalProcessorServicer):
    def Process(
        self,
        request_iterator: Iterator[service_pb2.ProcessingRequest],
        context: ServicerContext,
    ) -> Iterator[service_pb2.ProcessingResponse]:
        "Process the client request and add example headers"
        for request in request_iterator:
            if request.HasField("request_headers"):
                try:
                    scoped_headers = []
                    if environ.get("se_require_iap"):
                        if environ.get("se_test") == True:
                            scoped_headers.append("x-goog-iap-jwt-assertion-test")
                        else:
                            scoped_headers.append("x-goog-iap-jwt-assertion")
                    if environ.get("se_allowed_sources") or environ.get(
                        "se_denied_sources"
                    ):
                        if environ.get("se_test") == True:
                            scoped_headers.append("x-forwarded-for-test")
                        else:
                            scoped_headers.append("x-forwarded-for")

                    request_headers = request.request_headers.headers
                    print(scoped_headers)
                    for header in request_headers.headers:
                        print(f"Header name is => {header.key}")
                        header_value = header.value or header.raw_value.decode(
                            "utf-8", "ignore"
                        )
                        if header.key in scoped_headers:
                            response_generator = scoped_header_actions[header.key](
                                header_value
                            )
                            scoped_headers.remove(header.key)
                            if response_generator:
                                yield from response_generator
                                return
                        if not scoped_headers:
                            break

                    request_header_mutation = service_pb2.HeadersResponse()
                    request_header_mutation.response.clear_route_cache = True
                    yield service_pb2.ProcessingResponse(
                        request_headers=request_header_mutation
                    )
                except Exception as e:
                    print(f"An error occurred: {e}")


class HealthCheckServer(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        "Returns an empty page with 200 status code"
        self.send_response(200)
        self.end_headers()


def serve() -> None:
    "Run gRPC server and Health check server"
    health_server = HTTPServer(("0.0.0.0", HEALTH_CHECK_PORT), HealthCheckServer)
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=2))
    service_pb2_grpc.add_ExternalProcessorServicer_to_server(CalloutProcessor(), server)
    server_credentials = grpc.ssl_server_credentials(
        private_key_certificate_chain_pairs=[
            (SERVER_CERTIFICATE_KEY, SERVER_CERTIFICATE)
        ]
    )
    server.add_secure_port("0.0.0.0:%d" % EXT_PROC_SECURE_PORT, server_credentials)
    server.add_insecure_port("0.0.0.0:%d" % EXT_PROC_INSECURE_PORT)
    server.start()
    print(
        "Server started, listening on %d and %d"
        % (EXT_PROC_SECURE_PORT, EXT_PROC_INSECURE_PORT)
    )
    try:
        health_server.serve_forever()
    except KeyboardInterrupt:
        print("Server interrupted")
    finally:
        server.stop()
        health_server.server_close()


# [END serviceextensions_callout_add_header_main]
# [END serviceextensions_callout_add_header]
if __name__ == "__main__":
    # Run the gRPC service
    serve()
