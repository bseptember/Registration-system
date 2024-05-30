FROM smallstep/step-ca:hsm as stepca

FROM ubuntu:latest

RUN apt-get update -y
RUN apt-get install -y sudo
RUN apt-get install opensc -y
RUN apt-get install openssl -y
RUN apt-get install softhsm2 -y
RUN apt-get install nano -y
RUN apt-get install ca-certificates -y
RUN apt-get install netcat-openbsd -y

# Add step, step-ca, step-kms
COPY --from=stepca /usr/local/bin/* /usr/local/bin/

ENV CONFIGPATH="/root/.step/config/ca.json"
ENV PWDPATH="/root/.step/secrets/password"
ENV PKCS_URI='pkcs11:module-path=/usr/lib/softhsm/libsofthsm2.so;token=smallstep;id=1000;object=key?pin-value=password'

# Create default certificates and keys
ADD ca_init.sh ca.json .
RUN chmod a+x ca_init.sh

WORKDIR /root/.step/

# Use ca_init.sh and tail -f directly in CMD
CMD ["/bin/bash", "-c", "/ca_init.sh && while true; do sleep 3600; done"]
