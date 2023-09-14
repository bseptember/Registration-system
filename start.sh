#!/usr/bin/env bash
set -euo pipefail

# Function to generate root CA cert and key
generate_root_ca() {
    openssl ecparam -name prime256v1 -genkey -out rootCA.key
    openssl req -x509 -new -key rootCA.key -subj '/C=ZA/ST=Gauteng/O=Findme/CN=Findme RootCA' -sha256 -days 1024 -out rootCA.crt
}

# Function to generate IdP and LDAP certs
generate_certs() {
    # Generate IdP cert
    openssl ecparam -name prime256v1 -genkey -out oidc/conf/keycloak.key
    openssl req -new -key oidc/conf/keycloak.key -subj "/C=ZA/ST=Gauteng/O=Keycloak/CN=${LOCAL_IP}" -sha256 -out oidc/conf/keycloak.csr
    openssl x509 -req -in oidc/conf/keycloak.csr -CA rootCA.crt -CAkey rootCA.key -CAcreateserial -out oidc/conf/keycloak.crt -days 500 -sha256
    rm oidc/conf/keycloak.csr
    cat oidc/conf/keycloak.crt rootCA.crt > oidc/conf/fullchain.crt

    # Generate LDAP cert
    openssl ecparam -name prime256v1 -genkey -out ldap_mock/ldap.key
    openssl req -new -key ldap_mock/ldap.key -subj "/C=ZA/ST=Gauteng/O=Ldap/CN=${LOCAL_IP}" -sha256 -out ldap_mock/ldap.csr
    openssl x509 -req -in ldap_mock/ldap.csr -CA rootCA.crt -CAkey rootCA.key -CAcreateserial -out ldap_mock/ldap.crt -days 500 -sha256
    rm ldap_mock/ldap.csr
    cat ldap_mock/ldap.crt rootCA.crt > ldap_mock/fullchain.crt

    # Generate RabbitMQ cert
    openssl ecparam -name prime256v1 -genkey -out rabbitmq/rabbitmq.key
    openssl req -new -key rabbitmq/rabbitmq.key -subj "/C=ZA/ST=Gauteng/O=RabbitMQ/CN=${LOCAL_IP}" -sha256 -out rabbitmq/rabbitmq.csr
    openssl x509 -req -in rabbitmq/rabbitmq.csr -CA rootCA.crt -CAkey rootCA.key -CAcreateserial -out rabbitmq/rabbitmq.crt -days 500 -sha256
    rm rabbitmq/rabbitmq.csr
    cat rabbitmq/rabbitmq.crt rootCA.crt > rabbitmq/fullchain.crt
}



# Check if the files exist and prompt the user
if [[ -f rootCA.key && -f rootCA.crt ]]; then
    read -rp "The rootCA.key and rootCA.crt files already exist. Do you want to overwrite them? (y/n): " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        rm -f rootCA.key rootCA.crt
        generate_root_ca
    else
        echo "Files not overwritten. Continuing."
    fi
else
    generate_root_ca
fi

# Find the local IP address for the 'enp0s3' interface
LOCAL_IP=$(ifconfig enp0s3 | grep -oE 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -oE '([0-9]*\.){3}[0-9]*')

# Check if LOCAL_IP is empty
if [[ -n "$LOCAL_IP" ]]; then
    
    # Create or overwrite the .env file with the LOCAL_IP
    echo "LOCAL_IP=$LOCAL_IP" > .env
    echo "Using LOCAL_IP from ifconfig: LOCAL_IP=$LOCAL_IP"

else
    # Check if .env file exists and contains LOCAL_IP
    if [[ -f .env && $(cat .env) == *"LOCAL_IP="* ]]; then
        echo "Using .env with contents: $(cat .env)"
    else
        # Create .env with a default key pair
        echo "LOCAL_IP=127.0.0.1" > .env
        echo "Using default LOCAL_IP=127.0.0.1"
    fi
    # Read the LOCAL_IP value from .env file
    LOCAL_IP=$(grep -oE 'LOCAL_IP=[0-9\.]*' .env | cut -d'=' -f2)
fi

# Replace all IP addresses for the webapi and rabbitmq in the JSON file
sed -i "s/http:\/\/[0-9.]*:5120\//http:\/\/$LOCAL_IP:5120\//g" oidc/import/test-realm.json
sed -i "s/http:\/\/[0-9.]*:15672\//http:\/\/$LOCAL_IP:15672\//g" oidc/import/test-realm.json
sed -i "s/http:\/\/[0-9.]*:15672\//http:\/\/$LOCAL_IP:15672\//g" oidc/import/test-realm.json
sed -i "s/http:\/\/[0-9.]*:8080/http:\/\/$LOCAL_IP:8080/g" rabbitmq/rabbitmq.conf
sed -i "s/https:\/\/[0-9.]*:8443/https:\/\/$LOCAL_IP:8443/g" rabbitmq/rabbitmq.conf

# Generate IdP and LDAP certs
generate_certs
docker-compose up -d
