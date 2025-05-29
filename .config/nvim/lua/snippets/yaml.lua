local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local fmt = require("luasnip.extras.fmt").fmt

return {
  -- Basic YAML snippets with proper formatting
  
  -- Simple property
  s("prop", {
    t(""), i(1, "key"), t(": "), i(2, "value")
  }),

  -- List item
  s("item", {
    t("- "), i(1, "value")
  }),

  -- Object with properties
  s("obj", {
    i(1, "key"), t({": ", "  "}), i(2, "property"), t(": "), i(3, "value")
  }),

  -- Default patch FromCompositeFieldPath
  s("patch", fmt([[
- type: FromCompositeFieldPath
  fromFieldPath: {}
  toFieldPath: {}]], {
    i(1, "fromFieldPath"),
    i(2, "toFieldPath")
  })),

  -- Simple composition base
  s("compbase", fmt([[
- name: {}
  base:
    apiVersion: {}
    kind: {}
    spec:
      deletionPolicy: Orphan
      forProvider:
        {}
      providerConfigRef:
        name: {}]], {
    i(1, "resourceName"),
    i(2, "api/version"),
    i(3, "resourceKind"),
    i(4, "config"),
    i(5, "providerName")
  })),

  -- Basic definition property
  s("defprop", fmt([[
{}:
  type: {}
  description: {}]], {
    i(1, "propertyName"),
    i(2, "string"),
    i(3, "Property description")
  })),

  -- Basic Kubernetes resource
  s("k8s", fmt([[
apiVersion: {}
kind: {}
metadata:
  name: {}
  namespace: {}
spec:
  {}]], {
    i(1, "v1"),
    i(2, "Pod"),
    i(3, "resource-name"),
    i(4, "default"),
    i(0)
  }))
}