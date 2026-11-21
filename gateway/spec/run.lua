-- Executor mínimo de testes para os módulos Lua puros do gateway.
-- Uso: luajit spec/run.lua spec/policy_spec.lua [...]
-- Mantido sem dependências para rodar na própria imagem do Kong (luajit).
package.path = "plugins/?.lua;" .. package.path

local passed, failed = 0, 0
local current = ""

_G.describe = function(name, fn)
  local previous = current
  current = previous == "" and name or (previous .. " > " .. name)
  fn()
  current = previous
end

_G.it = function(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print("  ok   " .. current .. " > " .. name)
  else
    failed = failed + 1
    print("  FAIL " .. current .. " > " .. name .. "\n       " .. tostring(err))
  end
end

_G.assert_equal = function(expected, actual, label)
  if expected ~= actual then
    error(string.format("%s: expected %s, got %s", label or "value", tostring(expected), tostring(actual)), 2)
  end
end

for _, file in ipairs(arg) do
  print(file)
  dofile(file)
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
