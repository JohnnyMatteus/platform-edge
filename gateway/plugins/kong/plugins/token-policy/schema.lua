local typedefs = require "kong.db.schema.typedefs"

return {
  name = "token-policy",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { allowed_issuers = {
              type = "array", required = true, len_min = 1,
              elements = { type = "string" },
          } },
          { required_audience = { type = "string", required = false } },
          { roles_claim = { type = "string", required = true, default = "realm_access.roles" } },
          { required_roles = {
              type = "array", required = true, len_min = 1,
              elements = { type = "string" },
          } },
          { match = { type = "string", required = true, default = "any", one_of = { "any", "all" } } },
        },
    } },
  },
}
