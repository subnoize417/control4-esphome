local log = require("lib.logging")
local bindings = require("lib.bindings")
local values = require("lib.values")
local ESPHomeClient = require("esphome.client")
local ESPHomeProtoSchema = require("esphome.proto_schema")

--- @class CameraEntity:Entity
local CameraEntity = {
  TYPE = ESPHomeClient.EntityType.ESP32_CAMERA,
}
CameraEntity.__index = CameraEntity

--- Create a new instance of the camera entity.
--- @param client ESPHomeClient The ESPHome client instance.
--- @return CameraEntity entity A new instance of the CameraEntity entity.
function CameraEntity:new(client)
  local instance = setmetatable({}, self)
  instance.client = client
  return instance
end

--- Handle the discovery of a camera entity.
--- Exposes a BUTTON_LINK binding for snapshot requests since ESP32 cameras stream
--- JPEG frames over protobuf, not RTSP/MJPEG URLs that Control4's camera proxy expects.
--- @param entity table<string, any> The entity data received from the ESPHome client.
--- @return void
function CameraEntity:discovered(entity)
  log:trace("CameraEntity:discovered(%s)", entity)
  local bindingId = assert(
    bindings:getOrAddDynamicBinding(self.TYPE, "camera_" .. entity.key, "CONTROL", true, entity.name, "BUTTON_LINK")
  ).bindingId

  -- Update availability variable
  values:update(entity.name .. " Available", "1", "BOOL")

  RFP[bindingId] = function(idBinding, strCommand, tParams, args)
    log:trace("RFP idBinding=%s strCommand=%s tParams=%s args=%s", idBinding, strCommand, tParams, args)
    if strCommand == "DO_CLICK" then
      self.client
        :callServiceMethod(ESPHomeProtoSchema.RPC.APIConnection.camera_image, {
          single = true,
          stream = false,
        })
        :next(function()
          log:info("Snapshot request sent to %s.%s", entity.entity_type, entity.object_id)
        end, function(error)
          log:error(
            "An error occurred sending snapshot request to %s.%s; %s",
            entity.entity_type,
            entity.object_id,
            error
          )
        end)
    end
  end
  OBC[bindingId] = RefreshStatus
end

--- Handle a state update for a camera entity.
--- Camera image data arrives via CameraImageResponse (not the normal state subscription),
--- so this method primarily tracks availability. If a state update is received with image
--- data, it logs the frame size.
--- @param entity table<string, any> The entity data received from the ESPHome client.
--- @param state table<string, any> The state data received from the ESPHome client.
--- @return void
function CameraEntity:updated(entity, state)
  log:trace("CameraEntity:updated(%s, %s)", entity, state)
  -- Camera image data comes via CameraImageResponse (not the normal state subscription).
  -- If we do receive a state update, just log the data size.
  local data = state.data
  if data then
    log:info(
      "Received camera frame from %s.%s (%d bytes, done=%s)",
      entity.entity_type,
      entity.object_id,
      #data,
      tostring(state.done)
    )
  end
  values:update(entity.name .. " Available", "1", "BOOL")
end

return CameraEntity
