#!/usr/bin/env bash

cat > v3.txt <<- EOF
keyUsage = critical, digitalSignature, keyEncipherment, dataEncipherment, keyAgreement
extendedKeyUsage = serverAuth
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
subjectAltName = DNS:admission-controller.opa-istio.svc
EOF

openssl req -x509 \
  -subj "/CN=OPA Envoy plugin" \
  -nodes \
  -newkey rsa:4096 \
  -days 1826 \
  -keyout root.key \
  -out root.crt
openssl genrsa -out opa-envoy.key 4096
openssl req -new \
  -key opa-envoy.key \
  -subj "/CN=opa-envoy" \
  -reqexts SAN \
  -config <(cat /etc/ssl/openssl.cnf \
      <(printf "\n[SAN]\nsubjectAltName=DNS:admissin-controller.opa-istio.svc")) \
  -sha256 \
  -out opa-envoy.csr
openssl x509 -req \
  -extfile v3.txt \
  -CA root.crt \
  -CAkey root.key \
  -CAcreateserial \
  -days 1825 \
  -sha256 \
  -in opa-envoy.csr \
  -out opa-envoy.crt

rm v3.txt opa-envoy.csr root.key root.srl
