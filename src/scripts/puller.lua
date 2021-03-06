--
-- Puller
--
-- @author TyKonKet
-- @date 13/04/2017
Puller = {}
source(g_currentModDirectory .. "scripts/pullerEvents.lua")

function Puller.prerequisitesPresent(specializations)
    return true
end

function Puller:preLoad(savegame)
    self.getAttachmentsSaveNodes = Utils.overwrittenFunction(self.getAttachmentsSaveNodes, Puller.getAttachmentsSaveNodes)
    self.loadAttachmentFromNodes = Utils.overwrittenFunction(self.loadAttachmentFromNodes, Puller.loadAttachmentFromNodes)
    self.isDetachAllowed = Utils.overwrittenFunction(self.isDetachAllowed, Puller.isDetachAllowed)
    self.canBeGrabbed = Puller.canBeGrabbed
    self.getIsTurnedOn = Puller.getIsTurnedOn
    self.pulledVehicleThrottle = false
end

function Puller:load(savegame)
    self.isGrabbable = Utils.getNoNil(getXMLBool(self.xmlFile, "vehicle.grabbable#isGrabbable"), false)
    self.isGrabbableOnlyIfDetach = Utils.getNoNil(getXMLBool(self.xmlFile, "vehicle.grabbable#isGrabbableOnlyIfDetach"), false)
    self.attachPoint = Utils.indexToObject(self.components, getXMLString(self.xmlFile, "vehicle.puller#index"))
    self.attachPointCollision = Utils.indexToObject(self.components, getXMLString(self.xmlFile, "vehicle.puller#rootNode"))
    self.attachRadius = Utils.getNoNil(getXMLFloat(self.xmlFile, "vehicle.puller#attachRadius"), 1)
    self.isAttached = false
    self.joint = {}
    self.inRangeVehicle = nil
end

function Puller:getAttachmentsSaveNodes(superFunc, nodeIdent, vehiclesToId)
    local nodes = ""
    if superFunc ~= nil then
        nodes = superFunc(self, nodeIdent, vehiclesToId)
    end
    local id = vehiclesToId[self]
    if id ~= nil and self.joint ~= nil then
        local object = self.joint.object
        if object ~= nil and vehiclesToId[object] ~= nil and self.joint.attacherJointId ~= nil then
            nodes = nodes .. nodeIdent .. '<attachment id0="' .. id .. '" id1="' .. vehiclesToId[object] .. '" jointId="' .. self.joint.attacherJointId .. '" type="towbar" />\n'
        end
    end
    return nodes
end

function Puller:loadAttachmentFromNodes(superFunc, xmlFile, key, idsToVehicle)
    if superFunc ~= nil then
        superFunc(self, xmlFile, key, idsToVehicle)
    end
    local type = getXMLString(xmlFile, key .. "#type")
    if type == "towbar" then
        local id1 = getXMLString(xmlFile, key .. "#id1")
        local jointId = getXMLInt(xmlFile, key .. "#jointId")
        if id1 ~= nil and jointId ~= nil then
            local vehicle1 = idsToVehicle[id1]
            if vehicle1 ~= nil then
                Puller.onAttachObject(self, vehicle1, jointId, true)
            end
        end
    end
end

function Puller:delete()
end

function Puller:mouseEvent(posX, posY, isDown, isUp, button)
end

function Puller:keyEvent(unicode, sym, modifier, isDown)
end

function Puller:readStream(streamId, connection)
    if streamReadBool(streamId) then
        local jointId = streamReadInt32(streamId)
        local object = readNetworkNodeObject(streamId)
        Puller.onAttachObject(self, object, jointId, true)
    end
end

function Puller:writeStream(streamId, connection)
    streamWriteBool(streamId, self.isAttached)
    if self.isAttached then
        streamWriteInt32(streamId, self.joint.attacherJointId)
        writeNetworkNodeObject(streamId, self.joint.object)
    end
end

function Puller:update(dt)
    if self:getIsActiveForInput() then
        if self.inRangeVehicle ~= nil then
            if not self.isAttached then
                if InputBinding.hasEvent(InputBinding.IMPLEMENT_EXTRA2) then
                    Puller.onAttachObject(self, self.inRangeVehicle.vehicle, self.inRangeVehicle.index)
                    SoundUtil.playSample(self.sampleAttach, 1, 0, nil)
                end
            end
        else
            if self.isAttached then
                if InputBinding.hasEvent(InputBinding.IMPLEMENT_EXTRA2) then
                    if not self.pulledVehicleThrottle then
                        Puller.onDetachObject(self)
                        SoundUtil.playSample(self.sampleAttach, 1, 0, nil)
                    else
                        --g_currentMission:showBlinkingWarning(g_i18n:getText("PULLER_DISABLE_THROTTLE_WARNING"), 2000)
                        self.showDetachingNotAllowedTime = 2000
                    end
                end
            end
        end
        if self.isAttached then
            if self.pulledVehicleThrottle then
                if InputBinding.hasEvent(InputBinding.PULLER_TOGGLE_THROTTLE) then
                    self.pulledVehicleThrottle = false
                    if self.joint.object.reverserDirection ~= nil then
                        Puller.leaveVehicle(self.joint.object, self.joint.object.leaveVehicle)
                    elseif self.joint.object.attacherVehicle ~= nil and self.joint.object.attacherVehicle.reverserDirection ~= nil then
                        Puller.leaveVehicle(self.joint.object.attacherVehicle, self.joint.object.attacherVehicle.leaveVehicle)
                    end
                end
            else
                if InputBinding.hasEvent(InputBinding.PULLER_TOGGLE_THROTTLE) then
                    self.pulledVehicleThrottle = true
                end
            end
        end
    end
    if self.pulledVehicleThrottle then
        if self.joint.object.reverserDirection ~= nil then
            Drivable.updateVehiclePhysics(self.joint.object, self.attacherVehicle.axisForward, self.attacherVehicle.axisForwardIsAnalog, self.attacherVehicle.axisSide, self.attacherVehicle.axisSideIsAnalog, self.attacherVehicle.doHandbrake, dt)
        elseif self.joint.object.attacherVehicle ~= nil and self.joint.object.attacherVehicle.reverserDirection ~= nil then
            Drivable.updateVehiclePhysics(self.joint.object.attacherVehicle, self.attacherVehicle.axisForward, self.attacherVehicle.axisForwardIsAnalog, self.attacherVehicle.axisSide, self.attacherVehicle.axisSideIsAnalog, self.attacherVehicle.doHandbrake, dt)
        end
    end
end

function Puller:updateTick(dt)
    if self:getIsActiveForInput() and not self.isAttached then
        self.inRangeVehicle = nil
        local x, y, z = getWorldTranslation(self.attachPoint)
        for k, v in pairs(g_currentMission.vehicles) do
            local vx, vy, vz = getWorldTranslation(v.rootNode)
            if Utils.vector3Length(x - vx, y - vy, z - vz) <= 50 then
                for index, joint in pairs(v.attacherJoints) do
                    if joint.jointType == AttacherJoints.JOINTTYPE_TRAILER or joint.jointType == AttacherJoints.JOINTTYPE_TRAILERLOW then
                        local x1, y1, z1 = getWorldTranslation(joint.jointTransform)
                        local distance = Utils.vector3Length(x - x1, y - y1, z - z1)
                        if distance <= self.attachRadius then
                            self.inRangeVehicle = {}
                            self.inRangeVehicle.vehicle = v
                            self.inRangeVehicle.index = index
                            break
                        end
                    end
                end
                if v.attacherJoint ~= nil and self.inRangeVehicle == nil then
                    if v.attacherJoint.jointType == AttacherJoints.JOINTTYPE_TRAILER or v.attacherJoint.jointType == AttacherJoints.JOINTTYPE_TRAILERLOW then
                        local x1, y1, z1 = getWorldTranslation(v.attacherJoint.node)
                        local distance = Utils.vector3Length(x - x1, y - y1, z - z1)
                        if distance <= self.attachRadius then
                            self.inRangeVehicle = {}
                            self.inRangeVehicle.vehicle = v
                            self.inRangeVehicle.index = 0
                            break
                        end
                    end
                end
            end
        end
    end
end

function Puller:onAttachObject(object, jointId, noEventSend)
    PullerAttachEvent.sendEvent(self, object, jointId, noEventSend)
    if object.isBroken == true then
        object.isBroken = false
    end
    if self.isServer then
        local objectAttacherJoint = nil
        if jointId == 0 then
            objectAttacherJoint = object.attacherJoint
        else
            objectAttacherJoint = object.attacherJoints[jointId]
        end
        local constr = JointConstructor:new()
        constr:setActors(self.attachPointCollision, objectAttacherJoint.rootNode)
        constr:setJointTransforms(self.attachPoint, Utils.getNoNil(objectAttacherJoint.jointTransform, objectAttacherJoint.node))
        for i = 1, 3 do
            constr:setTranslationLimit(i - 1, true, 0, 0)
            constr:setRotationLimit(i - 1, -0.35, 0.35)
            constr:setEnableCollision(false)
        end
        self.joint.index = constr:finalize()
        if object.reverserDirection ~= nil then
            Puller.leaveVehicle(object, object.leaveVehicle)
        elseif object.attacherVehicle ~= nil and object.attacherVehicle.reverserDirection ~= nil then
            Puller.leaveVehicle(object.attacherVehicle, object.attacherVehicle.leaveVehicle)
        end
        self.joint.attacherJointId = jointId
        if object.leaveVehicle ~= nil then
            object.backupLeaveVehicle = object.leaveVehicle
            object.leaveVehicle = Utils.overwrittenFunction(object.leaveVehicle, Puller.leaveVehicle)
        elseif object.attacherVehicle ~= nil and object.attacherVehicle.leaveVehicle ~= nil then
            object.attacherVehicle.backupLeaveVehicle = object.attacherVehicle.leaveVehicle
            object.attacherVehicle.leaveVehicle = Utils.overwrittenFunction(object.attacherVehicle.leaveVehicle, Puller.leaveVehicle)
        end
    end
    object.forceIsActive = true
    self.joint.object = object
    self.isAttached = true
    self.inRangeVehicle = nil
end

function Puller:onDetachObject(noEventSend)
    PullerDetachEvent.sendEvent(self, noEventSend)
    if self.isServer then
        if self.joint.object.leaveVehicle ~= nil and self.joint.object.backupLeaveVehicle ~= nil then
            self.joint.object.leaveVehicle = self.joint.object.backupLeaveVehicle
            self.joint.object.backupLeaveVehicle = nil
        elseif self.joint.object.attacherVehicle.leaveVehicle ~= nil and self.joint.object.attacherVehicle.backupLeaveVehicle ~= nil then
            self.joint.object.attacherVehicle.leaveVehicle = self.joint.object.attacherVehicle.backupLeaveVehicle
            self.joint.object.attacherVehicle.backupLeaveVehicle = nil
        end
        removeJoint(self.joint.index)
        if not self.joint.object.isControlled and self.joint.object.motor ~= nil and self.joint.object.wheels ~= nil then
            for k, wheel in pairs(self.joint.object.wheels) do
                setWheelShapeProps(wheel.node, wheel.wheelShape, 0, self.joint.object.motor:getBrakeForce() * wheel.brakeFactor, 0, wheel.rotationDamping)
            end
        end
    end
    self.joint.object.forceIsActive = false
    self.joint = nil
    self.joint = {}
    self.isAttached = false
    self.pulledVehicleThrottle = false
end

function Puller:draw()
    if self.inRangeVehicle ~= nil then
        g_currentMission:addHelpButtonText(g_i18n:getText("PULLER_ATTACH"), InputBinding.IMPLEMENT_EXTRA2)
        g_currentMission:enableHudIcon("attach", 10)
    elseif self.inRangeVehicle == nil and self.isAttached then
        g_currentMission:addHelpButtonText(g_i18n:getText("PULLER_DETACH"), InputBinding.IMPLEMENT_EXTRA2)
    end
    if self.isAttached then
        if self.pulledVehicleThrottle then
            g_currentMission:addHelpButtonText(g_i18n:getText("PULLER_DISABLE_THROTTLE"), InputBinding.PULLER_TOGGLE_THROTTLE)
        else
            g_currentMission:addHelpButtonText(g_i18n:getText("PULLER_ENABLE_THROTTLE"), InputBinding.PULLER_TOGGLE_THROTTLE)
        end
    end
end

function Puller:canBeGrabbed()
    if self.isGrabbable then
        if self.isGrabbableOnlyIfDetach then
            if not self.isAttached and self.attacherVehicle == nil then
                return true
            end
        else
            return true
        end
    end
    return false
end

function Player:pickUpObjectRaycastCallback(hitObjectId, x, y, z, distance)
    if distance > 0.5 and distance <= Player.MAX_PICKABLE_OBJECT_DISTANCE then
        if hitObjectId ~= g_currentMission.terrainDetailId and Player.PICKED_UP_OBJECTS[hitObjectId] ~= true then
            if getRigidBodyType(hitObjectId) == "Dynamic" then
                local object = g_currentMission:getNodeObject(hitObjectId)
                if (object ~= nil and object.dynamicMountObject == nil) or g_currentMission.nodeToVehicle[hitObjectId] == nil then
                    self.lastFoundObject = hitObjectId
                    self.lastFoundObjectMass = getMass(hitObjectId)
                    self.lastFoundObjectHitPoint = {x, y, z}
                    return false
                end
                if g_currentMission.nodeToVehicle[hitObjectId].canBeGrabbed ~= nil and g_currentMission.nodeToVehicle[hitObjectId]:canBeGrabbed() then
                    self.lastFoundObject = hitObjectId
                    self.lastFoundObjectMass = Player.MAX_PICKABLE_OBJECT_MASS * 0.9
                    self.lastFoundObjectHitPoint = {x, y, z}
                    return false
                end
            end
        end
    end
    return true
end

function Player:throwObject()
    if self.pickedUpObject ~= nil and self.pickedUpObjectJointId ~= nil then
        self:pickUpObject(false)
        local dx, dy, dz = localDirectionToWorld(self.cameraNode, 0, 0, -1)
        local mass = getMass(self.pickedUpObject)
        local v = 8.0 * (1.1 - math.min(1, mass / Player.MAX_PICKABLE_OBJECT_MASS))
        local vx = dx * v
        local vy = dy * v
        local vz = dz * v
        setLinearVelocity(self.pickedUpObject, vx, vy, vz)
        local object = g_currentMission:getNodeObject(self.pickedUpObject)
        if object ~= nil then
            object.thrownFromPosition = {getWorldTranslation(g_currentMission.player.rootNode)}
        end
    end
end

function Player:pickUpObject(state, noEventSend)
    if self.isServer then
        if state and (self.isObjectInRange and self.lastFoundObject ~= nil) and not self.isCarryingObject then
            local constr = JointConstructor:new()
            constr:setActors(self.pickUpKinematicHelper.node, self.lastFoundObject)
            constr:setJointTransforms(self.pickUpKinematicHelper.node, self.lastFoundObject)

            for i = 0, 2 do
                constr:setRotationLimit(i, 0, 0)
                constr:setTranslationLimit(i, true, 0, 0)
            end

            local wx = self.lastFoundObjectHitPoint[1]
            local wy = self.lastFoundObjectHitPoint[2]
            local wz = self.lastFoundObjectHitPoint[3]
            constr:setJointWorldPositions(wx, wy, wz, wx, wy, wz)

            local nx, ny, nz = localDirectionToWorld(self.lastFoundObject, 1, 0, 0)
            constr:setJointWorldAxes(nx, ny, nz, nx, ny, nz)

            local yx, yy, yz = localDirectionToWorld(self.lastFoundObject, 0, 1, 0)
            constr:setJointWorldNormals(yx, yy, yz, yx, yy, yz)

            constr:setEnableCollision(false)

            local dampingRatio = 1.0
            local mass = getMass(self.lastFoundObject) * 100
            if getMass(self.lastFoundObject) > Player.MAX_PICKABLE_OBJECT_MASS * 0.9 then
                mass = getMass(self.lastFoundObject) * 0.4 * 100
            else
                mass = getMass(self.lastFoundObject) * 100
            end

            local rotationLimitSpring = {}
            local rotationLimitDamper = {}
            for i = 1, 3 do
                rotationLimitSpring[i] = mass * 60
                rotationLimitDamper[i] = dampingRatio * 2 * math.sqrt(mass * rotationLimitSpring[i])
            end
            constr:setRotationLimitSpring(rotationLimitSpring[1], rotationLimitDamper[1], rotationLimitSpring[2], rotationLimitDamper[2], rotationLimitSpring[3], rotationLimitDamper[3])

            local translationLimitSpring = {}
            local translationLimitDamper = {}
            for i = 1, 3 do
                translationLimitSpring[i] = mass * 60
                translationLimitDamper[i] = dampingRatio * 2 * math.sqrt(mass * translationLimitSpring[i])
            end
            constr:setTranslationLimitSpring(translationLimitSpring[1], translationLimitDamper[1], translationLimitSpring[2], translationLimitDamper[2], translationLimitSpring[3], translationLimitDamper[3])

            local forceAcceleration = 4
            local forceLimit = forceAcceleration * mass
            constr:setBreakable(forceLimit, forceLimit)
            self.pickedUpObjectJointId = constr:finalize()
            addJointBreakReport(self.pickedUpObjectJointId, "onPickedUpObjectJointBreak", self)

            self.pickedUpObject = self.lastFoundObject
            self.isCarryingObject = true
            Player.PICKED_UP_OBJECTS[self.pickedUpObject] = true
            local object = g_currentMission:getNodeObject(self.pickedUpObject)
            if object ~= nil then
                object.thrownFromPosition = nil
            end
        else
            if self.pickedUpObjectJointId ~= nil then
                removeJoint(self.pickedUpObjectJointId)
                self.pickedUpObjectJointId = nil
                self.isCarryingObject = false
                Player.PICKED_UP_OBJECTS[self.pickedUpObject] = false

                if entityExists(self.pickedUpObject) then
                    local vx, vy, vz = getLinearVelocity(self.pickedUpObject)
                    vx = Utils.clamp(vx, -5, 5)
                    vy = Utils.clamp(vy, -5, 5)
                    vz = Utils.clamp(vz, -5, 5)
                    setLinearVelocity(self.pickedUpObject, vx, vy, vz)
                end
                local object = g_currentMission:getNodeObject(self.pickedUpObject)
                if object ~= nil then
                    object.thrownFromPosition = nil
                end
            end
        end
    end
end

function Puller:leaveVehicle(superFunc)
    if superFunc ~= nil then
        superFunc(self)
    end
    if not self.isControlled and self.motor ~= nil and self.wheels ~= nil then
        for k, wheel in pairs(self.wheels) do
            setWheelShapeProps(wheel.node, wheel.wheelShape, 0, 0, 0, wheel.rotationDamping)
        end
    end
end

function Puller:getIsTurnedOn()
    return self.pulledVehicleThrottle
end

function Puller:isDetachAllowed()
    return self.pulledVehicleThrottle
end

function Puller:isDetachAllowed(superFunc)
    if superFunc ~= nil then
        if not superFunc(self) then
            return false
        end
    end
    return not self.pulledVehicleThrottle
end
