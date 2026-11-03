describe("harness registry", function()
  it("registers and returns adapters by name", function()
    local harness = require("agentdiff.harness")
    local fake = {
      name = "fake",
      parse = function(payload)
        return payload.file and { phase = "post", paths = { payload.file } } or nil
      end,
      install = function()
        return true
      end,
      uninstall = function()
        return true
      end,
      status = function()
        return { installed = false }
      end,
    }
    harness.register(fake)
    eq(fake, harness.get("fake"))
    ok(vim.tbl_contains(harness.names(), "fake"))
    eq({ phase = "post", paths = { "/p/x.lua" } }, harness.get("fake").parse({ file = "/p/x.lua" }))
    eq(nil, harness.get("nope"))
  end)
end)
