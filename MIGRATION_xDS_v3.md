# Notes on migrating to xDS v3 API (envoy.service.auth.v2.Authorization -> envoy.service.auth.v3.Authorization)

## CheckResponse fields

In v3, CheckResponse has gotten new fields:

- OkHttpResponse now has `headers_to_remove`
- OkHttpResponse and DenyHttpResponse have a `dynamic_metadata` field (deprecated in favour of the following)
- CheckResponse has a new field `dynamic_metadata`
- OKHttpResponse's and DenyHttpResponse's `headers` field has changed type from `api.v2.core.HeaderValueOption` to `config.core.v3.HeaderValueOption`, but those are structurally identical

Neither `headers_to_remove` nor controlling `dynamic_metadata` is supported in opa-envoy-plugin right now.

## CheckRequest fields

Both contain one field, `attributes` of type AttributeContext only, in a v2 and a v3 variant:

### AttributeContext.Peer (`attributes.source` and `attributes.destination`)

Identical, except for `address` being of type `api.v2.core.Address` and `config.core.v3.Address` respectively.
Those types are identical, the v3 variant has an added field `envoy_internal_address` that is not in use yet.

### AttributeContext.HttpRequest (`attributes.request.http`)

New field: `raw_body` (bytes):
 
```
// The HTTP request body in bytes. This is used instead of
// :ref:`body <envoy_v3_api_field_service.auth.v3.AttributeContext.HttpRequest.body>` when
// :ref:`pack_as_bytes <envoy_api_field_extensions.filters.http.ext_authz.v3.BufferSettings.pack_as_bytes>`
// is set to true.
```

### `attributes.metadata_context`

Switched types from `api.v2.core.Metadata` to `config.core.v3.Metadata`, structurally identical.
 
## Changes in the `input` to OPA policy evaluation

In the v2 implementation, opa-envoy-plugin used a mapping from protobuf to JSON that wasn't following the protobuf specification.

With the migration to v3, this is adjusted. The encoding changes for well-known types:

- `attributes.request.time` is `google.protobuf.Timestamp`
- `attributes.metadata_context.filter_metadata` is `map<string, google.protobuf.Struct`

as well as the encoding of "oneof" fields, and the mapping of protobuf message fields to JSON object keys.
See below for an example.

### Example CheckRequest v2 vs v3:

In v2, we'll find this `input`:
```
{
  "attributes": {
    "destination": {
      "address": {
        "Address": {
          "SocketAddress": {
            "PortSpecifier": {
              "PortValue": 51051
            },
            "address": "127.0.0.1"
          }
        }
      }
    },
    "metadata_context": {},
    "request": {
      "http": {
        "headers": {
          ":authority": "127.0.0.1:51051",
          ":method": "GET",
          ":path": "/foobar",
          "accept": "*/*",
          "user-agent": "curl/7.64.1",
          "x-forwarded-proto": "http",
          "x-request-id": "dabf7d84-2a1b-4bd4-aceb-d0e457abfd0b"
        },
        "host": "127.0.0.1:51051",
        "id": "3467646284090197720",
        "method": "GET",
        "path": "/foobar",
        "protocol": "HTTP/1.1"
      },
      "time": {
        "nanos": 722473000,
        "seconds": 1605865667
      }
    },
    "source": {
      "address": {
        "Address": {
          "SocketAddress": {
            "PortSpecifier": {
              "PortValue": 59052
            },
            "address": "127.0.0.1"
          }
        }
      }
    }
  }
}
```

In V3, the input will look like this:
```
{
  "attributes": {
    "source": {
      "address": {
        "socketAddress": {
          "address": "127.0.0.1",
          "portValue": 59052
        }
      }
    },
    "destination": {
      "address": {
        "socketAddress": {
          "address": "127.0.0.1",
          "portValue": 51051
        }
      }
    },
    "request": {
      "time": "2020-11-20T09:47:47.722473Z",
      "http": {
        "id": "3467646284090197720",
        "method": "GET",
        "headers": {
          ":authority": "127.0.0.1:51051",
          ":method": "GET",
          ":path": "/foobar",
          "accept": "*/*",
          "user-agent": "curl/7.64.1",
          "x-forwarded-proto": "http",
          "x-request-id": "dabf7d84-2a1b-4bd4-aceb-d0e457abfd0b"
        },
        "path": "/foobar",
        "host": "127.0.0.1:51051",
        "protocol": "HTTP/1.1"
      }
    },
    "metadataContext": {}
  }
}
```

Ordering aside, the V3 input matches the specified [JSON Mapping](https://developers.google.com/protocol-buffers/docs/proto3#json) for protocol buffers.
Notably:

- Keys are camelCase, starting with a lowercase letter (`Address` becomes `address`, `SocketAddress` becomes `socketAddress`, `metadata_context` becomes `metadataContext`)
- Timestamps are _strings_ following RFC3339, so `{ "time": { "nanos": 722473000, "seconds": 1605865667 }` becomes `"time": "2020-11-20T09:47:47.722473Z"`
- OneOf types are flattened, so the `address` fields of `source` and `destination` change from (v2)
```
{
  "source": {
    "address": {
      "Address": {
        "SocketAddress": {
          "PortSpecifier": {
            "PortValue": 59052
          },
          "address": "127.0.0.1"
        }
      }
    }
  }
}
```

to (v3):
```
{
  "source": {
    "address": {
      "socketAddress": {
        "address": "127.0.0.1",
        "portValue": 59052
      }
    }
  }
}
```

This means if your policy was using `input.attributes.source.address.Address.SocketAddress.address` with v2, it's got to be changed to `input.attributes.source.address.socketAddress.address`.

### Dynamic Metadata

In v2, the dynamic metadata injected by an JWT authn filter would look like this:

```
{
  "metadata_context": {
    "filter_metadata": {
      "envoy.filters.http.jwt_authn": {
        "verified_jwt": {
          "at_hash": "tQvbld0gQEnXznJOeUVHgQ",
          "aud": "example-app",
          "email": "kilgore@kilgore.trout",
          "email_verified": true,
          "exp": 1605955609,
          "iat": 1605869209,
          "iss": "http://127.0.0.1:5556/dex",
          "name": "Kilgore Trout",
          "sub": "Cg0wLTM4NS0yODA4OS0wEgRtb2Nr"
        }
      }
    }
  }
}
```

In v3, it turns into
```
{
  "metadataContext": {
    "filterMetadata": {
      "envoy.filters.http.jwt_authn": {
        "verified_jwt": {
          "at_hash": "tQvbld0gQEnXznJOeUVHgQ",
          "aud": "example-app",
          "email": "kilgore@kilgore.trout",
          "email_verified": true,
          "exp": 1605955609,
          "iat": 1605869209,
          "iss": "http://127.0.0.1:5556/dex",
          "name": "Kilgore Trout",
          "sub": "Cg0wLTM4NS0yODA4OS0wEgRtb2Nr"
        }
      }
    }
  }
}
```
