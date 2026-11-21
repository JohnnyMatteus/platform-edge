local policy = require "kong.plugins.token-policy.policy"

local ISSUER = "http://localhost:8080/realms/edge"

-- pairs() ignora valores nil; NONE marca um campo que deve ser removido.
local NONE = {}

local function merge(base, overrides)
  for k, v in pairs(overrides or {}) do
    if v == NONE then
      base[k] = nil
    else
      base[k] = v
    end
  end
  return base
end

local function conf(overrides)
  local c = {
    allowed_issuers = { ISSUER },
    required_audience = "edge-gateway",
    roles_claim = "realm_access.roles",
    required_roles = { "payments.read" },
    match = "any",
  }
  return merge(c, overrides)
end

local function claims(overrides)
  local c = {
    iss = ISSUER,
    aud = "edge-gateway",
    sub = "user-1",
    azp = "payments-ops",
    realm_access = { roles = { "payments.read" } },
  }
  return merge(c, overrides)
end

local function expect_denied(decision, status, reason)
  assert_equal(false, decision.allowed, "allowed")
  assert_equal(status, decision.status, "status")
  assert_equal(reason, decision.reason, "reason")
end

describe("token-policy", function()
  describe("happy path", function()
    it("allows a token from a trusted issuer with the required role", function()
      assert_equal(true, policy.evaluate(claims(), conf()).allowed, "allowed")
    end)

    it("accepts aud as a list (RFC 7519)", function()
      local d = policy.evaluate(claims({ aud = { "account", "edge-gateway" } }), conf())
      assert_equal(true, d.allowed, "allowed")
    end)

    it("skips the audience check when the route does not require one", function()
      local d = policy.evaluate(claims({ aud = NONE }), conf({ required_audience = NONE }))
      assert_equal(true, d.allowed, "allowed")
    end)
  end)

  describe("authentication failures return 401", function()
    it("denies when claims are missing", function()
      expect_denied(policy.evaluate(nil, conf()), 401, "claims_missing")
    end)

    it("denies an untrusted issuer", function()
      expect_denied(policy.evaluate(claims({ iss = "http://evil.example.com/realms/edge" }), conf()),
        401, "issuer_not_allowed")
    end)

    it("denies a non-string issuer", function()
      expect_denied(policy.evaluate(claims({ iss = { ISSUER } }), conf()), 401, "issuer_not_allowed")
    end)

    it("denies a token minted for another audience", function()
      expect_denied(policy.evaluate(claims({ aud = "account" }), conf()), 401, "audience_not_allowed")
    end)

    it("denies a token without aud when the route requires one", function()
      expect_denied(policy.evaluate(claims({ aud = NONE }), conf()), 401, "audience_not_allowed")
    end)
  end)

  describe("authorization failures return 403", function()
    it("denies when the user has none of the required roles", function()
      local c = claims({ realm_access = { roles = { "studios.read" } } })
      expect_denied(policy.evaluate(c, conf()), 403, "missing_role")
    end)

    it("denies when the roles claim is absent", function()
      expect_denied(policy.evaluate(claims({ realm_access = NONE }), conf()), 403, "missing_role")
    end)

    it("denies when the roles claim has the wrong shape", function()
      expect_denied(policy.evaluate(claims({ realm_access = "payments.read" }), conf()), 403, "missing_role")
    end)

    it("ignores non-string role entries", function()
      local c = claims({ realm_access = { roles = { 42, { "payments.read" } } } })
      expect_denied(policy.evaluate(c, conf()), 403, "missing_role")
    end)

    it("denies the default-deny sentinel role that nobody holds", function()
      expect_denied(policy.evaluate(claims(), conf({ required_roles = { "edge.deny-by-default" } })),
        403, "missing_role")
    end)
  end)

  describe("match modes", function()
    local admin_conf = conf({ required_roles = { "studios.read", "studios.admin" } })

    it("any: one matching role is enough", function()
      local c = claims({ realm_access = { roles = { "studios.read" } } })
      assert_equal(true, policy.evaluate(c, admin_conf).allowed, "allowed")
    end)

    it("all: every role is required", function()
      local all_conf = conf({ required_roles = { "studios.read", "studios.admin" }, match = "all" })
      local partial = claims({ realm_access = { roles = { "studios.read" } } })
      local full = claims({ realm_access = { roles = { "studios.admin", "studios.read" } } })
      expect_denied(policy.evaluate(partial, all_conf), 403, "missing_role")
      assert_equal(true, policy.evaluate(full, all_conf).allowed, "allowed")
    end)
  end)

  describe("roles claim path", function()
    it("reads client roles from a nested path", function()
      local c = claims({ resource_access = { ["payments-ops"] = { roles = { "refund" } } } })
      local d = policy.evaluate(c, conf({
        roles_claim = "resource_access.payments-ops.roles",
        required_roles = { "refund" },
      }))
      assert_equal(true, d.allowed, "allowed")
    end)

    it("denies when an intermediate node is not a table", function()
      local c = claims({ resource_access = "oops" })
      expect_denied(policy.evaluate(c, conf({ roles_claim = "resource_access.payments-ops.roles" })),
        403, "missing_role")
    end)
  end)
end)
