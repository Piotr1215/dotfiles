local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local c = ls.choice_node
local d = ls.dynamic_node
local r = ls.restore_node
local sn = ls.snippet_node
local fmt = require("luasnip.extras.fmt").fmt
local fmta = require("luasnip.extras.fmt").fmta

return {
  -- Create a component rectangle
  s("rec", {
    t("rectangle "), i(1, "name"), t(" as "), i(2, "as_name"), t(" {\\n"), i(0), t("\n}")
  }),

  -- Create a component rectangle from selected text
  s("recc", {
    t("rectangle "), i(1, "name"), t(" as "), i(2, "as_name"), t(" {\\n"), i(3, "$TM_SELECTED_TEXT"), i(0), t("}")
  }),

  -- Include C4 Context Diagram
  s("Include C4 Context Diagram", {
    t("!include https://raw.githubusercontent.com/plantuml-stdlib/C4-PlantUML/master/C4_Context.puml")
  }),

  -- Include C4 Container Diagram
  s("Include C4 Container Diagram", {
    t("!include https://raw.githubusercontent.com/plantuml-stdlib/C4-PlantUML/master/C4_Container.puml")
  }),

  -- Include C4 Component Diagram
  s("Include C4 Component Diagram", {
    t("!include https://raw.githubusercontent.com/plantuml-stdlib/C4-PlantUML/master/C4_Component.puml")
  }),

  -- Include C4 Deployment Diagram
  s("Include C4 Deployment Diagram", {
    t("!include https://raw.githubusercontent.com/plantuml-stdlib/C4-PlantUML/master/C4_Deployment.puml")
  }),

  -- Include C4 Dynamic Diagram
  s("Include C4 Dynamic Diagram", {
    t("!include https://raw.githubusercontent.com/plantuml-stdlib/C4-PlantUML/master/C4_Dynamic.puml")
  }),

  -- Add Person to C4 diagram
  s("Person", {
    t("Person("), i(1, "alias"), t(", \""), i(2, "label"), t("\")")
  }),

  -- Add Person with Description to C4 diagram
  s("Person with Description", {
    t("Person("), i(1, "alias"), t(", \""), i(2, "label"), t("\", \""), i(3, "description"), t("\")")
  }),

  -- Add External Person to C4 diagram
  s("External Person", {
    t("Person_Ext("), i(1, "alias"), t(", \""), i(2, "label"), t("\")")
  }),

  -- Add External Person with Description to C4 diagram
  s("External Person with Description", {
    t("Person_Ext("), i(1, "alias"), t(", \""), i(2, "label"), t("\", \""), i(3, "description"), t("\")")
  }),

  -- Add Container with Description to C4 diagram
  s("Container", {
    t("Container("), i(1, "alias"), t(", \""), i(2, "label"), t("\", \""), i(3, "technology"), t("\", \""), i(4, "description"), t("\")")
  }),

  -- Add External Container to C4 diagram
  s("External Container", {
    t("Container_Ext("), i(1, "alias"), t(", \""), i(2, "label"), t("\", \""), i(3, "technology"), t("\")")
  }),

  -- Add External Container with Description to C4 diagram
  s("External Container with Description", {
    t("Container_Ext("), i(1, "alias"), t(", \""), i(2, "label"), t("\", \""), i(3, "technology"), t("\", \""), i(4, "description"), t("\")")
  }),

  -- Add Database Container to C4 diagram
  s("Database Container", {
    t("ContainerDb("), i(1, "alias"), t(", \""), i(2, "label"), t("\", \""), i(3, "technology"), t("\")")
  }),

  -- Add Database Container with Description to C4 diagram
  s("Database Container with Description", {
    t("ContainerDb("), i(1, "alias"), t(", \""), i(2, "label"), t("\", \""), i(3, "technology"), t("\", \""), i(4, "description"), t("\")")
  }),

  -- Add External Database Container to C4 diagram
  s("External Database Container", {
    t("ContainerDb_Ext("), i(1, "alias"), t(", \""), i(2, "label"), t("\", \""), i(3, "technology"), t("\")")
  }),

  -- Add External Database Container with Description to C4 diagram
  s("External Database Container with Description", {
    t("ContainerDb_Ext("), i(1, "alias"), t(", \""), i(2, "label"), t("\", \""), i(3, "technology"), t("\", \""), i(4, "description"), t("\")")
  }),

  -- Add Queue Container to C4 diagram
  s("Queue Container", {
    t("ContainerQueue("), i(1, "alias"), t(", \""), i(2, "label"), t("\", \""), i(3, "technology"), t("\")")
  }),

  -- Add Queue Container with Description to C4 diagram
  s("Queue Container with Description", {
    t("ContainerQueue("), i(1, "alias"), t(", \""), i(2, "label"), t("\", \""), i(3, "technology"), t("\", \""), i(4, "description"), t("\")")
  }),

  -- Add External Queue Container to C4 diagram
  s("External Queue Container", {
    t("ContainerQueue_Ext("), i(1, "alias"), t(", \""), i(2, "label"), t("\", \""), i(3, "technology"), t("\")")
  }),

  -- Add ExternalQueue Container with Description to C4 diagram
  s("External Queue Container with Description", {
    t("ContainerQueue_Ext("), i(1, "alias"), t(", \""), i(2, "label"), t("\", \""), i(3, "technology"), t("\", \""), i(4, "description"), t("\")")
  }),

  -- Add a Container Boundary to C4 diagram
  s("Container Boundary", {
    t("Container_Boundary("), i(1, "alias"), t(", \""), i(2, "label"), t("\"){\\n	"), i(0), t("\\n}")
  }),

  -- Add Component to C4 diagram
  s("Component", {
    t("Component("), i(1, "alias"), t(", \""), i(2, "label"), t("\", \""), i(3, "technology"), t("\")")
  }),

  -- Add Component with Description to C4 diagram
  s("Component with Description", {
    t("Component("), i(1, "alias"), t(", \""), i(2, "label"), t("\", \""), i(3, "technology"), t("\", \""), i(4, "description"), t("\")")
  }),

  -- Add External Component to C4 diagram
  s("External Component", {
    t("Component_Ext("), i(1, "alias"), t(", \""), i(2, "label"), t("\", \""), i(3, "technology"), t("\")")
  }),

  -- Add External Component with Description to C4 diagram
  s("External Component with Description", {
    t("Component_Ext("), i(1, "alias"), t(", \""), i(2, "label"), t("\", \""), i(3, "technology"), t("\", \""), i(4, "description"), t("\")")
  }),

  -- Add Database Component to C4 diagram
  s("Database Component", {
    t("ComponentDb("), i(1, "alias"), t(", \""), i(2, "label"), t("\", \""), i(3, "technology"), t("\")")
  }),

  -- Add Database Component with Description to C4 diagram
  s("Database Component with Description", {
    t("ComponentDb("), i(1, "alias"), t(", \""), i(2, "label"), t("\", \""), i(3, "technology"), t("\", \""), i(4, "description"), t("\")")
  }),

  -- Add External Database Component to C4 diagram
  s("External Database Component", {
    t("ComponentDb_Ext("), i(1, "alias"), t(", \""), i(2, "label"), t("\", \""), i(3, "technology"), t("\")")
  }),

  -- Add External Database Component with Description to C4 diagram
  s("External Database Component with Description", {
    t("ComponentDb_Ext("), i(1, "alias"), t(", \""), i(2, "label"), t("\", \""), i(3, "technology"), t("\", \""), i(4, "description"), t("\")")
  }),

  -- Add Queue Component to C4 diagram
  s("Queue Component", {
    t("ComponentQueue("), i(1, "alias"), t(", \""), i(2, "label"), t("\", \""), i(3, "technology"), t("\")")
  }),

  -- Add Queue Component with Description to C4 diagram
  s("Queue Component with Description", {
    t("ComponentQueue("), i(1, "alias"), t(", \""), i(2, "label"), t("\", \""), i(3, "technology"), t("\", \""), i(4, "description"), t("\")")
  }),

  -- Add External Queue Component to C4 diagram
  s("External Queue Component", {
    t("ComponentQueue_Ext("), i(1, "alias"), t(", \""), i(2, "label"), t("\", \""), i(3, "technology"), t("\")")
  }),

  -- Add External Queue Component with Description to C4 diagram
  s("External Queue Component with Description", {
    t("ComponentQueue_Ext("), i(1, "alias"), t(", \""), i(2, "label"), t("\", \""), i(3, "technology"), t("\", \""), i(4, "description"), t("\")")
  }),

  -- Add System to C4 diagram
  s("System", {
    t("System("), i(1, "alias"), t(", \""), i(2, "label"), t("\")")
  }),

  -- Add System with Description to C4 diagram
  s("Systemdesc", {
    t("System("), i(1, "alias"), t(", \""), i(2, "label"), t("\", \""), i(3, "description"), t("\")")
  }),

  -- Add External System to C4 diagram
  s("External System", {
    t("System_Ext("), i(1, "alias"), t(", \""), i(2, "label"), t("\")")
  }),

  -- Add External System with Description to C4 diagram
  s("External System with Description", {
    t("System_Ext("), i(1, "alias"), t(", \""), i(2, "label"), t("\", \""), i(3, "description"), t("\")")
  }),

  -- Add Database System to C4 diagram
  s("Database System", {
    t("SystemDb("), i(1, "alias"), t(", \""), i(2, "label"), t("\")")
  }),

  -- Add Database System with Description to C4 diagram
  s("Database System with Description", {
    t("SystemDb("), i(1, "alias"), t(", \""), i(2, "label"), t("\", \""), i(3, "description"), t("\")")
  }),

  -- Add External Database System to C4 diagram
  s("External Database System", {
    t("SystemDb_Ext("), i(1, "alias"), t(", \""), i(2, "label"), t("\")")
  }),

  -- Add External Database System with Description to C4 diagram
  s("External Database System with Description", {
    t("SystemDb_Ext("), i(1, "alias"), t(", \""), i(2, "label"), t("\", \""), i(3, "description"), t("\")")
  }),

  -- Add Queue System to C4 diagram
  s("Queue System", {
    t("SystemQueue("), i(1, "alias"), t(", \""), i(2, "label"), t("\")")
  }),

  -- Add Queue System with Description to C4 diagram
  s("Queue System with Description", {
    t("SystemQueue("), i(1, "alias"), t(", \""), i(2, "label"), t("\", \""), i(3, "description"), t("\")")
  }),

  -- Add External Queue System to C4 diagram
  s("External Queue System", {
    t("SystemQueue_Ext("), i(1, "alias"), t(", \""), i(2, "label"), t("\")")
  }),

  -- Add External Queue System with Description to C4 diagram
  s("External Queue System with Description", {
    t("SystemQueue_Ext("), i(1, "alias"), t(", \""), i(2, "label"), t("\", \""), i(3, "description"), t("\")")
  }),

  -- Add a System Boundary to C4 diagram
  s("System Boundary", {
    t("System_Boundary("), i(1, "alias"), t(", \""), i(2, "label"), t("\"){\\n	"), i(0), t("\\n}")
  }),

  -- Add a System Boundary to C4 diagram
  s("sysbs", {
    t("System_Boundary("), i(1, "alias"), t(", \""), i(2, "label"), t("\"){\\n	"), i(3, "$TM_SELECTED_TEXT"), t("\\n	"), i(0), t("\\n}")
  }),

  -- Add an Enterprise Boundary to C4 diagram
  s("Enterprise Boundary", {
    t("Enterprise_Boundary("), i(1, "alias"), t(", \""), i(2, "label"), t("\"){\\n	"), i(0), t("\\n}")
  }),

  -- Add unidirectional Relationship to C4 diagram
  s("rel", {
    t("Rel("), i(1, "from_alias"), t(", "), i(2, "to_alias"), t(", \""), i(3, "label"), t("\")")
  }),

  -- Add unidirectional Relationship with Technology to C4 diagram
  s("Relationship with Technology", {
    t("Rel("), i(1, "from_alias"), t(", "), i(2, "to_alias"), t(", \""), i(3, "label"), t("\", \""), i(4, "technology"), t("\")")
  }),

  -- Add bidirectional Relationship to C4 diagram
  s("Bidirectional Relationship", {
    t("BiRel("), i(1, "from_alias"), t(", "), i(2, "to_alias"), t(", \""), i(3, "label"), t("\")")
  }),

  -- Add bidirectional Relationship with Technology to C4 diagram
  s("Bidirectional Relationship with Technology", {
    t("BiRel("), i(1, "from_alias"), t(", "), i(2, "to_alias"), t(", \""), i(3, "label"), t("\", \""), i(4, "technology"), t("\")")
  }),

  -- Add unidirectional Relationship to C4 Dynamic Diagram
  s("Relationship with Index", {
    t("RelIndex("), i(1, "index"), t(", "), i(2, "from_alias"), t(", "), i(3, "to_alias"), t(", \""), i(4, "label"), t("\")")
  }),

  -- Add unidirectional Relationship with Technology to C4 Dynamic Diagram
  s("Relationship with Technology and Index", {
    t("RelIndex("), i(1, "index"), t(", "), i(2, "from_alias"), t(", "), i(3, "to_alias"), t(", \""), i(4, "label"), t("\", \""), i(5, "technology"), t("\")")
  }),

  -- Add hidden layout line to put {to} to the right of {from}
  s("Layout to Right side", {
    t("Lay_R("), i(1, "from_alias"), t(", "), i(2, "to_alias"), t(")")
  }),

  -- Add hidden layout line to put {to} to the left of {from}
  s("Layout to Left side", {
    t("Lay_L("), i(1, "from_alias"), t(", "), i(2, "to_alias"), t(")")
  }),

  -- Add a generic boundary to C4 diagram.
  s("Boundary", {
    t("Boundary("), i(1, "alias"), t(", \""), i(2, "label"), t("\"){\\n	"), i(0), t("\\n}")
  }),

  -- Add a generic boundary to C4 diagram.
  s("Boundary with type", {
    t("Boundary("), i(1, "alias"), t(", \""), i(2, "label"), t("\", \""), i(3, "type"), t("\"){\\n	"), i(0), t("\\n}")
  }),

  -- Add a deployment node to C4 diagram.
  s("Deployment Node", {
    t("Deployment_Node("), i(1, "alias"), t(", \""), i(2, "label"), t("\"){\\n	"), i(0), t("\\n}")
  }),

  -- Add a deployment node to C4 diagram.
  s("Deployment Node with type", {
    t("Deployment_Node("), i(1, "alias"), t(", \""), i(2, "label"), t("\", \""), i(3, "type"), t("\"){\\n	"), i(0), t("\\n}")
  }),

  -- Increment index of C4 Dynamic Diagram.
  s("Increment index", {
    t("increment("), i(1, "count"), t(")")
  }),

  -- Set index of C4 Dynamic Diagram
  s("Set index", {
    t("setIndex("), i(1, "value"), t(")")
  }),

  -- Hide stereotypes from C4 diagram..
  s("Hide stereotype", {
    t("HIDE_STEREOTYPE()")
  }),

  -- Add legend to C4 diagram.
  s("Layout with legend", {
    t("LAYOUT_WITH_LEGEND()")
  }),

  -- Left to right layout for C4 diagram.
  s("Layout left to right", {
    t("LAYOUT_LEFT_RIGHT()")
  }),

  -- Top down layout for C4 diagram.
  s("Layout top down", {
    t("LAYOUT_TOP_DOWN()")
  }),

  -- Sketch layout for C4 diagram.
  s("Layout as sketch", {
    t("LAYOUT_AS_SKETCH()")
  }),

}