local log = require("lib.logging")
local values = require("lib.values")
local ESPHomeClient = require("esphome.client")
local ESPHomeProtoSchema = require("esphome.proto_schema")

--- Registry of discovered update entities for programming commands.
--- Maps display name to { key = number, client = ESPHomeClient }
--- @type table<string, { key: number, client: ESPHomeClient }>
local updateRegistry = {}

--- @class UpdateEntity:Entity
local UpdateEntity = {
  TYPE = ESPHomeClient.EntityType.UPDATE,
}
UpdateEntity.__index = UpdateEntity

--- Create a new instance of the update entity.
--- @param client ESPHomeClient The ESPHome client instance.
--- @return UpdateEntity entity A new instance of the UpdateEntity entity.
function UpdateEntity:new(client)
  local instance = setmetatable({}, self)
  instance.client = client
  return instance
end

--- Handle the discovery of an update entity.
--- @param entity table<string, any> The entity data received from the ESPHome client.
--- @return void
function UpdateEntity:discovered(entity)
  log:trace("UpdateEntity:discovered(%s)", entity)

  -- Register update entity for programming commands
  updateRegistry[entity.name] = {
    key = entity.key,
    client = self.client,
  }
end

--- Handle updates to the update entity state.
--- @param entity table<string, any> The entity data received from the ESPHome client.
--- @param state table<string, any> The state data received from the ESPHome client.
--- @return void
function UpdateEntity:updated(entity, state)
  log:trace("UpdateEntity:updated(%s, %s)", entity, state)

  if state.missing_state then
    return
  end

  local currentVersion = state.current_version or ""
  local latestVersion = state.latest_version or ""
  local updateAvailable = latestVersion ~= "" and currentVersion ~= latestVersion

  values:update(entity.name .. " Current Version", currentVersion, "STRING")
  values:update(entity.name .. " Latest Version", latestVersion, "STRING")
  values:update(entity.name .. " Update Available", updateAvailable and "1" or "0", "BOOL")

  if state.in_progress and state.has_progress then
    local progress = math.floor((state.progress or 0) * 100 + 0.5)
    values:update(entity.name .. " Update Progress", tostring(progress), "NUMBER")
  else
    values:update(entity.name .. " Update Progress", "0", "NUMBER")
  end
end

--- Get sorted list of update entity names for programming commands.
--- @return string[] names List of update entity display names.
local function getUpdateNames()
  local names = TableKeys(updateRegistry)
  table.sort(names)
  return names
end

--- Send an update command to the specified entity.
--- @param entityName string The display name of the update entity.
--- @param command number The update command enum value.
--- @param commandName string The human-readable command name for logging.
local function sendUpdateCommand(entityName, command, commandName)
  local entry = updateRegistry[entityName]
  if not entry then
    log:warn("%s command called for unknown update entity: %s", commandName, entityName)
    return
  end

  entry.client
    :callServiceMethod(ESPHomeProtoSchema.RPC.APIConnection.update_command, {
      key = entry.key,
      command = command,
    })
    :next(function()
      log:debug("Command %s sent to update entity %s", commandName, entityName)
    end, function(error)
      log:error("An error occurred sending command %s to update entity %s; %s", commandName, entityName, error)
    end)
end

--- Populate the Update parameter dropdown for the Check for Updates command.
--- @param paramName string The parameter name being requested.
--- @return string[] list List of update entity names.
function GCPL.Check_for_Updates(paramName)
  log:trace("GCPL.Check_for_Updates(%s)", paramName)
  if paramName ~= "Update" then
    return {}
  end
  return getUpdateNames()
end

--- Execute the Check for Updates command.
--- @param params table<string, any> Command parameters containing Update name.
function EC.Check_for_Updates(params)
  log:trace("EC.Check_for_Updates(%s)", params)
  local entityName = Select(params, "Update")
  if IsEmpty(entityName) then
    log:warn("Check for Updates command called without entity name")
    return
  end

  sendUpdateCommand(entityName, ESPHomeProtoSchema.Enum.UpdateCommand.UPDATE_COMMAND_CHECK, "Check for Updates")
end

--- Populate the Update parameter dropdown for the Install Update command.
--- @param paramName string The parameter name being requested.
--- @return string[] list List of update entity names.
function GCPL.Install_Update(paramName)
  log:trace("GCPL.Install_Update(%s)", paramName)
  if paramName ~= "Update" then
    return {}
  end
  return getUpdateNames()
end

--- Execute the Install Update command.
--- @param params table<string, any> Command parameters containing Update name.
function EC.Install_Update(params)
  log:trace("EC.Install_Update(%s)", params)
  local entityName = Select(params, "Update")
  if IsEmpty(entityName) then
    log:warn("Install Update command called without entity name")
    return
  end

  sendUpdateCommand(entityName, ESPHomeProtoSchema.Enum.UpdateCommand.UPDATE_COMMAND_UPDATE, "Install Update")
end

return UpdateEntity
