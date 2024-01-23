#!/usr/bin/env bash
set -euo pipefail
REMOTE_CLIENT_IP=192.168.8.181

# Start step ca container and generate self signed CA and intemediate cert
generate_root_ca() {
    cd stepca
    docker rm -f stepca
    docker build --no-cache -t stepca:latest -f Dockerfile .
    docker run -d \
    --name stepca \
    --network host \
    --privileged \
    --volume ./modify/oidc.sh:/home/oidc.sh \
    stepca:latest
    
    cd ../
 	
    # wait till the files exist before copying over to volume
    sleep 10

    docker cp stepca:/root/.step/certs/. certs
    docker cp stepca:/root/.step/secrets/. certs
}

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
sed -i "s/https:\/\/[0-9.]*:15671\//https:\/\/$LOCAL_IP:15671\//g" oidc/import/test-realm.json
sed -i "s/http:\/\/[0-9.]*:15672\//http:\/\/$LOCAL_IP:15672\//g" oidc/import/test-realm.json
sed -i 's|ldap://[0-9.]*:3890|ldap://'"$LOCAL_IP"':3890|g' oidc/import/test-realm.json
sed -i '/"rabbit_url": \[/{N;s/"[0-9.]\+"/"'$LOCAL_IP'"/}' oidc/import/test-realm.json
sed -i "s/http:\/\/[0-9.]*:8080/http:\/\/$LOCAL_IP:8080/g" rabbitmq/rabbitmq.conf
sed -i "s/https:\/\/[0-9.]*:8443/https:\/\/$LOCAL_IP:8443/g" rabbitmq/rabbitmq.conf
sed -E -i "s/([0-9]{1,3}\.){3}[0-9]{1,3}/$LOCAL_IP/g" stepca/ca.json

# Function to generate leaf certs
generate_certs() {
    if [[ -n "$LOCAL_IP" ]]; then
                
        docker exec -it stepca sh -c "mkdir -p /root/.step/data"
        
        # Generate keycloak cert
        docker exec -it stepca sh -c "cd data && step ca certificate --force --issuer admin --password-file /root/.step/secrets/password $LOCAL_IP oidc.crt oidc.key"
    
        # Generate LDAP cert
        docker exec -it stepca sh -c "cd data && step ca certificate --force --issuer admin --password-file /root/.step/secrets/password $LOCAL_IP ldap.crt ldap.key"
    
        # Generate PhpLDAP cert
        docker exec -it stepca sh -c "cd data && step ca certificate --force --issuer admin --password-file /root/.step/secrets/password $LOCAL_IP phpldap.crt phpldap.key"
    
        # Generate RabbitMQ cert
        docker exec -it stepca sh -c "cd data && step ca certificate --force --issuer admin -password-file /root/.step/secrets/password $LOCAL_IP rabbitmq.crt rabbitmq.key"
        
        # Generate custom cert for your pc
        docker exec -it stepca sh -c "cd data && step ca certificate --force --issuer admin --password-file /root/.step/secrets/password $REMOTE_CLIENT_IP custom.crt custom.key"

        # Copy all certs to host drive
        docker cp stepca:/root/.step/data/. certs

        # Generate p12 for custom cert
        #docker exec -it stepca sh -c "cd data && step certificate p12 --no-password --insecure custom.p12 custom.crt custom.key"
	    openssl pkcs12 -export -out certs/custom.p12 -inkey certs/custom.key -in certs/custom.crt -passout pass:1234567890 -certpbe aes-256-cbc -keypbe aes-256-cbc
        
        # Create a full chain intermediate certificate
        cat certs/root_ca.crt >> certs/intermediate_ca.crt

	    # Ensure files are usable on services in docker containers
	    chmod -R 777 certs/*	
    
    else
        echo "Error: LOCAL_IP is empty or not defined."
    fi
}

# Check if the files exist and prompt the user
if docker exec stepca [ -f "/root/.step/certs/root_ca.crt" ] && docker exec stepca [ -f "/root/.step/secrets/root_ca_key" ]; then
    read -rp "The root_ca.crt and root_ca_key files already exist. Do you want to overwrite them? (y/n): " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        docker rm -f stepca
        generate_root_ca
    else
        echo "Root CA not overwritten. Continuing."
    fi
else
    generate_root_ca
fi

if docker exec stepca [ -d "/root/.step/data" ]; then
    read -rp "Certs already exist. Do you want to overwrite them? (y/n): " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        generate_certs
    else
        echo "Certs not overwritten. Continuing."
    fi
else
    generate_certs
fi

docker-compose up -d
docker logs -f stepca
