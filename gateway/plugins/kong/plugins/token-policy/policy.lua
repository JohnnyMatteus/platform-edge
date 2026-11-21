-- Política de autorização pura: recebe as claims de um JWT já validado
-- (assinatura e expiração conferidas pelo plugin jwt) e decide se a
-- requisição pode seguir. Não depende do Kong, para ser testável com luajit.
local M = {}

local DENY_UNTRUSTED = 401
local DENY_FORBIDDEN = 403

-- Resolve um caminho pontuado ("realm_access.roles") dentro das claims.
local function claim_at(claims, path)
  local node = claims
  for key in string.gmatch(path, "[^%.]+") do
    if type(node) ~= "table" then
      return nil
    end
    node = node[key]
  end
  return node
end

local function to_set(list)
  local set = {}
  if type(list) ~= "table" then
    return set
  end
  for _, value in ipairs(list) do
    if type(value) == "string" then
      set[value] = true
    end
  end
  return set
end

local function contains(list, value)
  for _, item in ipairs(list) do
    if item == value then
      return true
    end
  end
  return false
end

-- "aud" pode ser string ou lista (RFC 7519, seção 4.1.3).
local function audience_matches(aud, required)
  if type(aud) == "string" then
    return aud == required
  end
  if type(aud) == "table" then
    return contains(aud, required)
  end
  return false
end

local function roles_satisfied(granted, required, match)
  if match == "all" then
    for _, role in ipairs(required) do
      if not granted[role] then
        return false
      end
    end
    return true
  end
  for _, role in ipairs(required) do
    if granted[role] then
      return true
    end
  end
  return false
end

local function deny(status, reason, message)
  return { allowed = false, status = status, reason = reason, message = message }
end

--- Avalia as claims contra a configuração da rota.
-- @param claims tabela de claims do token
-- @param conf { allowed_issuers, required_audience?, roles_claim, required_roles, match }
-- @return { allowed = true } ou { allowed = false, status, reason, message }
function M.evaluate(claims, conf)
  if type(claims) ~= "table" then
    return deny(DENY_UNTRUSTED, "claims_missing", "Unauthorized")
  end

  if type(claims.iss) ~= "string" or not contains(conf.allowed_issuers, claims.iss) then
    return deny(DENY_UNTRUSTED, "issuer_not_allowed", "Unauthorized")
  end

  if conf.required_audience and not audience_matches(claims.aud, conf.required_audience) then
    return deny(DENY_UNTRUSTED, "audience_not_allowed", "Unauthorized")
  end

  local granted = to_set(claim_at(claims, conf.roles_claim))
  if not roles_satisfied(granted, conf.required_roles, conf.match) then
    return deny(DENY_FORBIDDEN, "missing_role", "Forbidden")
  end

  return { allowed = true }
end

return M
