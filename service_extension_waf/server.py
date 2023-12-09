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
# Example Service Extension WAF
----
This server does two things:
* Validates that the provided IAP JWT is valid
-- Environment flag: se_require_iap
--- Default Value: False
* Validates that the Clients Source IP is
-- Explicitly Allowed (if allowed ranges are specified only specified source ranges are allowed, regardless if they match a denied range or not)
--- Environment flag: se_allowed_ipv4_cidr_ranges
--- Default Value: 0.0.0.0/0
-- Explicitly Denied
--- Environment flag: se_denied_ipv4_cidr_ranges
--- Default Value: None

Debug can be enabled by
-- Environment flag: se_debug
--- Default Value: False
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
from ipaddress import ip_network, ip_address, get_mixed_type_key

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

IAP_CERTIFICATE = open("./iap_public_key.crt", "rb").read()

SERVICE_EXTENSION_DEBUG = environ.get("se_debug", "False").lower() == ("true")
SERVICE_EXTENSION_TEST = environ.get("se_test", "False").lower() == ("true")
SERVICE_EXTENSION_REQUIRE_IAP = environ.get("se_require_iap", "False").lower() == (
    "true"
)

SERVICE_EXTENSION_ALLOWED_IPV4_CIDR_ENABLED = environ.get("se_allowed_ipv4_cidr_ranges")
SERVICE_EXTENSION_ALLOWED_IPV4_CIDR_RANGES = environ.get(
    "se_allowed_ipv4_cidr_ranges", "0.0.0.0/0"
)

SERVICE_EXTENSION_DENIED_IPV4_CIDR_ENABLED = environ.get("se_denied_ipv4_cidr_ranges")
SERVICE_EXTENSION_DENIED_IPV4_CIDR_RANGES = environ.get("se_denied_ipv4_cidr_ranges")

# Declare global variable
global_sorted_ipv4_cidr_ranges = None
global_formatted_ipv4_cidr_ranges = None


if SERVICE_EXTENSION_DEBUG:
    print(f"Service Extension Test Mode: {SERVICE_EXTENSION_TEST}")
    print(f"Service Extension Require IAP: {SERVICE_EXTENSION_REQUIRE_IAP}")
    print(
        f"Service Extension Allowed Source Ranges: {SERVICE_EXTENSION_ALLOWED_IPV4_CIDR_RANGES}"
    )
    print(
        f"Service Extension Denied Source Ranges: {SERVICE_EXTENSION_DENIED_IPV4_CIDR_RANGES}"
    )


def sort_ipv4_cidr_ranges() -> None:
    global global_sorted_ipv4_cidr_ranges
    global global_formatted_ipv4_cidr_ranges
    allowed_ipv4_cidr_ranges = []
    denied_ipv4_cidr_ranges = []

    if SERVICE_EXTENSION_ALLOWED_IPV4_CIDR_RANGES:
        allowed_ipv4_cidr_ranges = [
            allowed_ipv4_cidr.strip()
            for allowed_ipv4_cidr in SERVICE_EXTENSION_ALLOWED_IPV4_CIDR_RANGES.split(
                ","
            )
            if allowed_ipv4_cidr.strip()
        ]
    if SERVICE_EXTENSION_DENIED_IPV4_CIDR_RANGES:
        denied_ipv4_cidr_ranges = [
            denied_ipv4_cidr.strip()
            for denied_ipv4_cidr in SERVICE_EXTENSION_DENIED_IPV4_CIDR_RANGES.split(",")
            if denied_ipv4_cidr.strip()
        ]

    combined_ipv4_cidr_ranges = [
        (ip_network(cidr), "deny") for cidr in denied_ipv4_cidr_ranges
    ] + [(ip_network(cidr), "allow") for cidr in allowed_ipv4_cidr_ranges]

    global_sorted_ipv4_cidr_ranges = sorted(
        combined_ipv4_cidr_ranges,
        key=lambda x: get_mixed_type_key(x[0]),
        reverse=True,
    )

    if SERVICE_EXTENSION_DEBUG:
        global_formatted_ipv4_cidr_ranges = [
            (str(cidr_network), action)
            for cidr_network, action in global_sorted_ipv4_cidr_ranges
        ]
        print(
            f"Service Extension XFF Header sorted CIDR Ranges: {global_formatted_ipv4_cidr_ranges}"
        )
    return None


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


def validate_iap_jwt(iap_jwt):
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
            audience=None,
            certs_url="http://127.0.0.1:8000/iap_public_key.crt",
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
    user_id, user_email, error_str = validate_iap_jwt(header_value)
    if error_str:
        if SERVICE_EXTENSION_DEBUG:
            print(f"Service Extension IAP Header was invalid: {error_str}")
        return custom_response(
            service_pb2.StatusCode.Unauthorized,
            "Either the JWT token is invalid or was not provided",
        )
    if SERVICE_EXTENSION_DEBUG:
        print(f"Service Extension IAP Header was valid")
    return None  # Return if no Validation Issue


def handle_xff_validation(header_value):
    allow_request = False
    deny_request = False
    matched_ipv4_cidr = None
    xff_list = [ip.strip() for ip in header_value.split(",") if ip.strip()]

    if len(xff_list) >= 2:
        client_ipv4 = ip_address(xff_list[-2])
        for cidr, action in global_sorted_ipv4_cidr_ranges:
            if client_ipv4 in cidr:
                matched_ipv4_cidr = cidr
                if action == "allow":
                    allow_request = True
                    deny_request = False
                elif action == "deny":
                    allow_request = False
                    deny_request = True
                break

        if SERVICE_EXTENSION_DEBUG:
            print(
                f"Service Extension XFF Header sorted CIDR Ranges: {global_formatted_ipv4_cidr_ranges}"
            )
            print(
                f"""Service Extension XFF Header result:
                    Source IPv4: {client_ipv4}
                    Deny Request: {deny_request}
                    Allow Request: {allow_request}
                    Matched IPv4 CIDR: {matched_ipv4_cidr}"""
            )

        if not allow_request and not deny_request:
            if SERVICE_EXTENSION_DEBUG:
                print(
                    f"Service Extension XFF Header for source ip ({client_ipv4}) did not match any allowed ranges"
                )
            return custom_response(
                service_pb2.StatusCode.Forbidden,
                f"Requests for source ip ({client_ipv4}) was not allowed",
            )

        if deny_request:
            if SERVICE_EXTENSION_DEBUG:
                print(
                    f"Service Extension XFF Header for source ip ({client_ipv4}) matched ({matched_ipv4_cidr}) denied range"
                )
            return custom_response(
                service_pb2.StatusCode.Forbidden,
                f"Requests for source ip ({client_ipv4}) was denied",
            )
    return None  # Return if no Validation Issue


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
                    debug_headers = [":path", ":method", ":scheme", ":authority"]
                    IAP_JWT_HEADER = "x-goog-iap-jwt-assertion"
                    if SERVICE_EXTENSION_REQUIRE_IAP:
                        if SERVICE_EXTENSION_TEST:
                            IAP_JWT_HEADER = "x-goog-iap-jwt-assertion-test"

                        if SERVICE_EXTENSION_DEBUG:
                            print(f"Service Extension IAP Header: {IAP_JWT_HEADER}")
                        scoped_headers.append(IAP_JWT_HEADER)

                    XFF_HEADER = "x-forwarded-for"
                    if (
                        SERVICE_EXTENSION_ALLOWED_IPV4_CIDR_ENABLED
                        or SERVICE_EXTENSION_DENIED_IPV4_CIDR_ENABLED
                    ):
                        if SERVICE_EXTENSION_TEST:
                            XFF_HEADER = "x-forwarded-for-test"

                        if SERVICE_EXTENSION_DEBUG:
                            print(f"Service Extension XFF Header: {XFF_HEADER}")
                        scoped_headers.append(XFF_HEADER)

                    request_headers = request.request_headers.headers

                    if SERVICE_EXTENSION_DEBUG:
                        print(f"Service Extension in Scope Headers: {scoped_headers}")
                        print(f"Service Extension in Debug Headers: {debug_headers}")

                    for header in request_headers.headers:
                        if header.key in scoped_headers or (
                            SERVICE_EXTENSION_DEBUG and header.key in debug_headers
                        ):
                            header_value = header.value or header.raw_value.decode(
                                "utf-8", "ignore"
                            )

                            if SERVICE_EXTENSION_DEBUG:
                                header_type = (
                                    "Scoped"
                                    if header.key in scoped_headers
                                    else "Debug"
                                )
                                print(
                                    f"Service Extension {header_type} Header: ({header.key}), Value: ({header_value})"
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
                    # Checks if IAP was required but header was not detected
                    if SERVICE_EXTENSION_REQUIRE_IAP and (
                        IAP_JWT_HEADER in scoped_headers
                    ):
                        if SERVICE_EXTENSION_DEBUG:
                            print(
                                f"Service Extension IAP Required Header but Not Found"
                            )
                        response_generator = scoped_header_actions[IAP_JWT_HEADER]("")
                        if response_generator:
                            yield from response_generator
                            return

                    request_header_mutation = service_pb2.HeadersResponse()
                    request_header_mutation.response.clear_route_cache = True
                    yield service_pb2.ProcessingResponse(
                        request_headers=request_header_mutation
                    )
                except Exception as e:
                    print(f"An error occurred: {e}")


class HealthCheckServer(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        # Check if the request is for the specific file
        if self.path == "/iap_public_key.crt":
            try:
                self.send_response(200)
                self.send_header("Content-type", "application/x-x509-ca-cert")
                self.end_headers()
                self.wfile.write(IAP_CERTIFICATE)
            except FileNotFoundError:
                # Handle the case where the file is not found
                self.send_response(404)
                self.end_headers()
                self.wfile.write(b"File not found")
        else:
            # Default response for other paths
            self.send_response(200)
            self.send_header("Content-type", "text/html")
            self.end_headers()
            self.wfile.write(b"OK")

    def log_message(self, format, *args):
        # Override to suppress request logging
        pass  # Do nothing here


def serve() -> None:
    sort_ipv4_cidr_ranges()
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
