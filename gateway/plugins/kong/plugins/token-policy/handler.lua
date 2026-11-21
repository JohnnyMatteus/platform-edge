-- Plugin token-policy: autorização por papel e por rota sobre o JWT que o
-- plugin jwt (prioridade 1450) já autenticou. Roda antes do rate limit
-- (910), então uma requisição negada não consome a cota do cliente.
local jwt_parser = require "kong.plugins.jwt.jwt_parser"
local policy = require "kong.plugins.token-policy.policy"

local SUBJECT_HEADER = "X-Authenticated-Subject"

local TokenPolicyHandler = {
  PRIORITY = 1000,
  VERSION = "0.1.0",
}

function TokenPolicyHandler:access(conf)
  -- Nunca confie em um cabeçalho de identidade vindo do cliente.
  kong.service.request.clear_header(SUBJECT_HEADER)

  local token = kong.ctx.shared.authenticated_jwt_token
  if not token then
    -- Falha fechada: sem o plugin jwt na frente, ninguém passa.
    kong.log.warn("token-policy without an authenticated jwt; check plugin wiring")
    return kong.response.exit(401, { message = "Unauthorized" })
  end

  local jwt, err = jwt_parser:new(token)
  if not jwt then
    kong.log.warn("token-policy could not parse token: ", err)
    return kong.response.exit(401, { message = "Unauthorized" })
  end

  local decision = policy.evaluate(jwt.claims, conf)
  if not decision.allowed then
    local route = kong.router.get_route()
    kong.log.notice("token-policy denied reason=", decision.reason,
                    " route=", route and route.name or "unknown",
                    " azp=", tostring(jwt.claims.azp))
    return kong.response.exit(decision.status, { message = decision.message })
  end

  if type(jwt.claims.sub) == "string" then
    kong.service.request.set_header(SUBJECT_HEADER, jwt.claims.sub)
  end
end

return TokenPolicyHandler
