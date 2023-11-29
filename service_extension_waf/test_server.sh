#!/bin/bash
set -e

pytest test_server.py::test_server_health_check -sv

pytest test_server.py::test_server -sv \
    --se_test_case="Verify traffic is not denied" \
    --se_result="pass" \
    --se_headers='[{":host":"se-waf.demo.com"},{"x-forwarded-for":"1.1.1.1,2.2.2.2"}]'

pytest test_server.py::test_server -sv \
    --se_test_case="Verify only allowed ranges are allowed" \
    --se_result="pass" \
    --se_headers='[{":host":"se-waf.demo.com"},{"x-forwarded-for":"1.1.1.1,2.2.2.2"}]' \
    --se_allowed_ipv4_cidr_ranges='1.1.1.1/32'

pytest test_server.py::test_server -sv \
    --se_test_case="Verify denied ranges are blocked" \
    --se_result="fail" \
    --se_headers='[{":host":"se-waf.demo.com"},{"x-forwarded-for":"1.1.1.1,2.2.2.2"}]' \
    --se_denied_ipv4_cidr_ranges='1.0.0.0/8'
    
pytest test_server.py::test_server -sv \
    --se_test_case="Verify more specific CIDR ranges are allowed" \
    --se_result="pass" \
    --se_headers='[{":host":"se-waf.demo.com"},{"x-forwarded-for":"1.1.1.1,2.2.2.2"}]' \
    --se_denied_ipv4_cidr_ranges='1.0.0.0/8' \
    --se_allowed_ipv4_cidr_ranges='1.1.1.1/32'

pytest test_server.py::test_server -sv \
    --se_test_case="Verify only allowed ranges are allowed" \
    --se_result="pass" \
    --se_headers='[{":host":"se-waf.demo.com"},{"x-forwarded-for":"1.1.1.1,2.2.2.2"}]' \
    --se_allowed_ipv4_cidr_ranges='1.1.1.1/32'

pytest test_server.py::test_server -sv \
    --se_test_case="Verify missing IAP Header is blocked" \
    --se_result="fail" \
    --se_headers='[{":host":"se-waf.demo.com"},{"x-forwarded-for":"1.1.1.1,2.2.2.2"}]' \
    --se_require_iap='True'
    
pytest test_server.py::test_server -sv \
    --se_test_case="Verify incorrect IAP Header is blocked" \
    --se_result="fail" \
    --se_headers='[{":host":"se-waf.demo.com"},{"x-forwarded-for":"1.1.1.1,2.2.2.2"},{"x-goog-iap-jwt-assertion":"foo"}]' \
    --se_require_iap='True'

pytest test_server.py::test_server_health_check -sv