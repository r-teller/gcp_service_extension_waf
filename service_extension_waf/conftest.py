def pytest_addoption(parser):
    parser.addoption("--se_debug", action="store", default="True")
    parser.addoption("--se_require_iap", action="store", default=None)
    parser.addoption("--se_allowed_ipv4_cidr_ranges", action="store", default=None)
    parser.addoption("--se_denied_ipv4_cidr_ranges", action="store", default=None)
    
    
    parser.addoption("--se_test_case", action="store")
    
    ## Example = '[{":host":"se-waf.demo.com"},{"x-forwarded-for":"1.1.1.1,2.2.2.2"}]'
    parser.addoption("--se_headers", action="store", default=None)

    ## ENUM = [pass,fail]
    parser.addoption("--se_result", action="store")


def pytest_configure(config):
    import os

    os.environ["se_debug"] = config.getoption("--se_debug")
    
    headers = config.getoption("--se_headers")
    if headers is not None:
        os.environ["se_headers"] = headers

    result = config.getoption("--se_result")        
    if result is not None:
        os.environ["se_result"] = result

    test_case = config.getoption("--se_test_case")     
    if test_case is not None:
        os.environ["se_test_case"] = test_case

    require_iap = config.getoption("--se_require_iap")
    if require_iap is not None:
        os.environ["se_require_iap"] = require_iap

    allowed_ranges = config.getoption("--se_allowed_ipv4_cidr_ranges")
    if allowed_ranges is not None:
        os.environ["se_allowed_ipv4_cidr_ranges"] = allowed_ranges

    denied_ranges = config.getoption("--se_denied_ipv4_cidr_ranges")
    if denied_ranges is not None:
        os.environ["se_denied_ipv4_cidr_ranges"] = denied_ranges

