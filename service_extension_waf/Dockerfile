# Copyright 2023 Google, LLC.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
FROM debian:bookworm-slim
WORKDIR /home/callouts
COPY . .
RUN apt-get update && apt-get install -y python3-pip python3-grpc-tools curl
RUN pip install --break-system-packages  -r ./requirements.txt -r ./requirements-test.txt
RUN chmod +x ./test_server.sh
## On build download the latest IAP Certificate that is used to validate IAP JWT
RUN curl https://www.gstatic.com/iap/verify/public_key -o ./iap_public_key.crt

## Health Checkport
EXPOSE 8000

## Unsecure Port
EXPOSE 8080

## Secure Port
EXPOSE 8443
CMD [ "/usr/bin/python3", "server.py" ]