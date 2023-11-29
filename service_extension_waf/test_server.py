from __future__ import print_function

import threading
import urllib.request
import grpc
import pytest

import server
import service_pb2
import service_pb2_grpc

from os import environ
from typing import Iterator, List, Tuple


def get_request(
    end_of_stream: bool = False,
    is_request_header: bool = True,
    custom_headers: List[Tuple[str, str]] = [],
) -> service_pb2.ProcessingRequest:
    """Returns a ProcessingRequest"""

    if is_request_header:
        headers_map = service_pb2.HeaderMap(
            headers=[
                service_pb2.HeaderValue(key=key, raw_value=bytes(value, "utf-8"))
                for key, value in custom_headers
            ]
        )
        _headers = service_pb2.HttpHeaders(
            headers=headers_map,
            end_of_stream=end_of_stream,
        )
        request = service_pb2.ProcessingRequest(
            request_headers=_headers,
            async_mode=False,
        )
        return request
    return None


def get_requests_stream(
    custom_headers: List[Tuple[str, str]]
) -> Iterator[service_pb2.ProcessingRequest]:
    """Generator for requests stream"""
    request = get_request(
        end_of_stream=True,
        is_request_header=True,
        custom_headers=custom_headers,
    )
    yield request
    # Add additional requests if needed


# @pytest.fixture(scope="session", autouse=True)
@pytest.fixture(scope="module")
def setup_and_teardown() -> None:
    thread = None
    try:
        thread = threading.Thread(target=server.serve)
        thread.daemon = True
        thread.start()
        # Wait for the server to start
        thread.join(timeout=5)
        yield
    finally:
        if thread is not None:
            # Stop the server
            del thread


def test_with_custom_headers(headers: List[Tuple[str, str]]) -> None:
    """Test function that creates a channel and sends a request with custom headers."""
    channel = grpc.insecure_channel(f"0.0.0.0:{server.EXT_PROC_INSECURE_PORT}")
    result = environ.get("se_result").lower()
    test_case  = environ.get("se_test_case")
    try:
        stub = service_pb2_grpc.ExternalProcessorStub(channel)
        for response in stub.Process(get_requests_stream(headers)):
            str_message = str(response)
            print(str_message)
            print(result)
            if result == "fail":
                assert response.HasField("immediate_response")
            else:
                assert response.HasField("request_headers")
    except Exception as e:
        print(f"An error occurred: {e}")
        raise Exception(f"Test '{test_case}': was expected to {result}")
    finally:
        channel.close()


import json


@pytest.mark.usefixtures("setup_and_teardown")
def test_server() -> None:
    headers_str = environ.get("se_headers", "[]")
    headers_json = json.loads(headers_str)
    headers_tuple: List[Tuple[str, str]] = [(key, value) for d in headers_json for key, value in d.items()]

    test_with_custom_headers(headers_tuple)


@pytest.mark.usefixtures("setup_and_teardown")
def test_server_health_check() -> None:
    try:
        response = urllib.request.urlopen(f"http://0.0.0.0:{server.HEALTH_CHECK_PORT}")
        assert response.read() == b"OK"
        print(f"Verify Health Check Status: {response.getcode()}")
        assert response.getcode() == 200
        response = urllib.request.urlopen(
            f"http://0.0.0.0:{server.HEALTH_CHECK_PORT}/iap_public_key.crt"
        )
        assert response.getcode() == 200
        print(f"Verify IAP Cert downloaded: {response.read().decode('utf-8')}")
    except urllib.error.URLError:
        raise Exception("Setup Error: Server not ready!")


if __name__ == "__main__":
    # Run the gRPC service tests
    test_server()
