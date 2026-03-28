local log = require("lib.logging")
local values = require("lib.values")
local ESPHomeClient = require("esphome.client")
local ESPHomeProtoSchema = require("esphome.proto_schema")

--- Registry of discovered cameras for the Request Snapshot programming command.
--- Maps display name to { key = number, client = ESPHomeClient }
--- @type table<string, fun(): Deferred<void, string>>
local cameraRegistry = {}

--- Pending frame buffers keyed by entity key.
--- CameraImageResponse can arrive in multiple chunks; we accumulate until done=true.
--- @type table<number, string[]>
local frameBuffers = {}

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
  instance._callbackRegistered = false
  return instance
end

--- Register a one-time callback for CameraImageResponse.
--- CameraImageResponse does not match the *StateResponse$ pattern used by
--- subscribeStates(), so we register our own callback to receive frames.
--- @return void
function CameraEntity:_ensureImageCallback()
  if self._callbackRegistered then
    return
  end
  self._callbackRegistered = true

  local schema = ESPHomeProtoSchema.Message.CameraImageResponse
  local callbackKey = self.client:_makeMessageCallbackKey(schema)
  self.client:_registerCallback(callbackKey, function(message)
    local key = message.key
    local data = message.data or ""
    local done = message.done

    if not frameBuffers[key] then
      frameBuffers[key] = {}
    end
    table.insert(frameBuffers[key], data)

    if done then
      local totalSize = 0
      for _, chunk in ipairs(frameBuffers[key]) do
        totalSize = totalSize + #chunk
      end
      frameBuffers[key] = nil
      log:info("Received complete camera frame for key %s (%d bytes)", key, totalSize)
    end
  end)
end

--- Handle the discovery of a camera entity.
--- Exposes an availability variable and a programming command for snapshot requests.
--- ESP32 cameras stream JPEG frames over protobuf, not RTSP/MJPEG URLs that
--- Control4's camera proxy expects, so we expose a simple snapshot action instead.
--- @param entity table<string, any> The entity data received from the ESPHome client.
--- @return void
function CameraEntity:discovered(entity)
  log:trace("CameraEntity:discovered(%s)", entity)

  -- Track availability
  values:update(entity.name .. " Available", "1", "BOOL")

  -- Register callback for image responses (once across all cameras)
  self:_ensureImageCallback()

  -- Register camera for Request Snapshot programming command
  cameraRegistry[entity.name] = function()
    return self.client:callServiceMethod(ESPHomeProtoSchema.RPC.APIConnection.camera_image, {
      single = true,
      stream = false,
    })
  end
end

--- Handle a state update for a camera entity.
--- CameraImageResponse is handled via a dedicated callback registered in
--- _ensureImageCallback(). This method is a no-op since camera state updates
--- do not come through the normal subscribeStates() path.
--- @param entity table<string, any> The entity data received from the ESPHome client.
--- @param state table<string, any> The state data received from the ESPHome client.
--- @return void
function CameraEntity:updated(entity, state)
  log:trace("CameraEntity:updated(%s, %s)", entity, state)
end

--- Get sorted list of camera names for programming commands.
--- @return string[] names List of camera display names.
local function getCameraNames()
  local names = TableKeys(cameraRegistry)
  table.sort(names)
  return names
end

--- Populate the Camera parameter dropdown for the Request Snapshot command.
--- @param paramName string The parameter name being requested.
--- @return string[] list List of camera names.
function GCPL.Request_Snapshot(paramName)
  log:trace("GCPL.Request_Snapshot(%s)", paramName)
  if paramName ~= "Camera" then
    return {}
  end
  return getCameraNames()
end

--- Execute the Request Snapshot command.
--- @param params table<string, any> Command parameters containing Camera name.
function EC.Request_Snapshot(params)
  log:trace("EC.Request_Snapshot(%s)", params)
  local cameraName = Select(params, "Camera")
  if IsEmpty(cameraName) then
    log:warn("Request Snapshot command called without camera name")
    return
  end

  local requestSnapshot = cameraRegistry[cameraName]
  if not requestSnapshot then
    log:warn("Request Snapshot command called for unknown camera: %s", cameraName)
    return
  end

  requestSnapshot():next(function()
    log:info("Snapshot request sent to camera %s", cameraName)
  end, function(error)
    log:error("An error occurred sending snapshot request to camera %s; %s", cameraName, error)
  end)
end

return CameraEntity
