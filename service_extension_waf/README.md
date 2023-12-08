## Service Extension WAF (Web Application Firewall)

### Overview
This Python application serves as a lightweight Web Application Firewall (WAF) implementation, primarily designed for Google Cloud Platform (GCP) environments. It leverages gRPC (Google Remote Procedure Call) for processing HTTP requests and responses as part of a filter chain in an Envoy proxy setup.

### Key Features
- **IAP JWT Validation**: Validates Identity-Aware Proxy (IAP) JSON Web Tokens (JWTs) to ensure they are valid. This feature can be controlled using the environment flag `se_require_iap`, which defaults to `False`.
- **Source IP Validation**: Checks whether the client's source IP is explicitly allowed or denied based on a comma separated list of specified IPv4 CIDR ranges.
  - This feature is controlled by the flags `se_allowed_ipv4_cidr_ranges` (default: `0.0.0.0/0`) and `se_denied_ipv4_cidr_ranges` (default: None).
- **Debugging**: Offers debugging capabilities, which can be enabled through the `se_debug` environment flag, defaulting to `False`.

### Environment Variables
| Environment Variable          | Default Value | Description                                                                  | Acceptable Values                                           |
| ----------------------------- | ------------- | ---------------------------------------------------------------------------- | ----------------------------------------------------------- |
| `se_debug`                    | `False`       | Enables or disables debug logging.                                           | `True`, `False`                                             |
| `se_test`                     | `False`       | Activates test mode, which may alter certain behaviors for testing purposes. | `True`, `False`                                             |
| `se_require_iap`              | `False`       | Enables or disables the validation of IAP JWTs.                              | `True`, `False`                                             |
| `se_allowed_ipv4_cidr_ranges` | `0.0.0.0\0`   | Specifies the IPv4 CIDR ranges that are explicitly allowed.                  | List of CIDR ranges (e.g., `192.168.1.0/24,192.168.2.0/24`) |
| `se_denied_ipv4_cidr_ranges`  | None          | Specifies the IPv4 CIDR ranges that are explicitly denied.                   | List of CIDR ranges (e.g., `192.168.1.0/24`)                |

### Components
- **gRPC Server**: The core of the application, handling incoming processing requests and generating appropriate responses.
- **Health Check Server**: A simple HTTP server responding to health check requests, crucial for cloud deployments like on GCP's Cloud Run or Kubernetes Engine (GKE).

### Ports
- **Secure Port (`EXT_PROC_SECURE_PORT`)**: Default `8443`, for backend services on GCE VMs, GKE, and hybrid.
- **Insecure Port (`EXT_PROC_INSECURE_PORT`)**: Default `8080`, mainly for backend services on Cloud Run.
- **Health Check Port (`HEALTH_CHECK_PORT`)**: Default `8000`, for cloud health checks.

### Running the Server
Execute the script to start both the gRPC server and the health check server:
```bash
python3 ./server.py
```