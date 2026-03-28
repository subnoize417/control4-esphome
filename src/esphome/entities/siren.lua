local log = require("lib.logging")
local bindings = require("lib.bindings")
local values = require("lib.values")
local ESPHomeClient = require("esphome.client")
local ESPHomeProtoSchema = require("esphome.proto_schema")

--- @class SirenEntity:Entity
local SirenEntity = {
  TYPE = ESPHomeClient.EntityType.SIREN,
}
SirenEntity.__index = SirenEntity

--- Create a new instance of the siren entity.
--- @param client ESPHomeClient The ESPHome client instance.
--- @return SirenEntity entity A new instance of the SirenEntity entity.
function SirenEntity:new(client)
  local instance = setmetatable({}, self)
  instance.client = client
  return instance
end

--- Handle the discovery of a siren entity.
--- @param entity table<string, any> The entity data received from the ESPHome client.
--- @return void
function SirenEntity:discovered(entity)
  log:trace("SirenEntity:discovered(%s)", entity)
  local bindingId = assert(
    bindings:getOrAddDynamicBinding(self.TYPE, "siren_" .. entity.key, "PROXY", true, entity.name, "RELAY")
  ).bindingId

  RFP[bindingId] = function(idBinding, strCommand, tParams, args)
    log:trace("RFP idBinding=%s strCommand=%s tParams=%s args=%s", idBinding, strCommand, tParams, args)
    local state
    if strCommand == "ON" or strCommand == "CLOSE" then
      state = true
    elseif strCommand == "OFF" or strCommand == "OPEN" then
      state = false
    elseif strCommand == "TOGGLE" then
      state = not toboolean(Select(values:getValue(entity.name .. " State"), "value"))
    end

    self.client
      :callServiceMethod(ESPHomeProtoSchema.RPC.APIConnection.siren_command, {
        key = entity.key,
        has_state = true,
        state = state,
      })
      :next(function()
        log:debug("Command %s sent to %s.%s", state and "on" or "off", entity.entity_type, entity.object_id)
      end, function(error)
        log:error(
          "An error occurred sending command %s to %s.%s; %s",
          state and "on" or "off",
          entity.entity_type,
          entity.object_id,
          error
        )
      end)
  end
  OBC[bindingId] = RefreshStatus
end

--- Handle updates to the siren entity state.
--- @param entity table<string, any> The entity data received from the ESPHome client.
--- @param state table<string, any> The state data received from the ESPHome client.
--- @return void
function SirenEntity:updated(entity, state)
  log:trace("SirenEntity:updated(%s, %s)", entity, state)

  local value = toboolean(state.state)
  values:update(entity.name .. " State", value and "1" or "0", "BOOL", function(newValue)
    -- Convert the Control4 value (0/1 string) to a boolean for ESPHome
    local boolValue = toboolean(newValue)
    self.client
      :callServiceMethod(ESPHomeProtoSchema.RPC.APIConnection.siren_command, {
        key = entity.key,
        has_state = true,
        state = boolValue,
      })
      :next(function()
        log:info("Commanded %s.%s to %s", entity.entity_type, entity.object_id, boolValue and "on" or "off")
      end, function(error)
        log:error(
          "Failed to command %s.%s to %s: %s",
          entity.entity_type,
          entity.object_id,
          boolValue and "on" or "off",
          error
        )
      end)
  end)

  -- Update the relay proxy
  local relayBinding = bindings:getDynamicBinding(self.TYPE, "siren_" .. entity.key)
  if relayBinding ~= nil then
    SendToProxy(relayBinding.bindingId, value and "CLOSED" or "OPENED", {}, "NOTIFY")
  end
end

return SirenEntity
