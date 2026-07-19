local suites = {
  dofile("test/AppWindowCycler_test.lua"),
  dofile("test/kanata_test.lua"),
}

local total = 0
local failed = 0

for _, suite in ipairs(suites) do
  for _, test in ipairs(suite.tests) do
    total = total + 1
    local ok, err = pcall(test.run)
    if ok then
      print("ok - " .. test.name)
    else
      failed = failed + 1
      print("not ok - " .. test.name)
      print(err)
    end
  end
end

if failed > 0 then
  error(string.format("%d of %d tests failed", failed, total), 0)
end

print(string.format("%d tests passed", total))
