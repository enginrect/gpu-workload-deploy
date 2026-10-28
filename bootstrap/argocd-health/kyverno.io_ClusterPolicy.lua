hs = {}
-- Kyverno ClusterPolicy: status.ready(구버전 · RIC 집계) 또는 conditions[Ready](1.17은 conditions만 기록)
if obj.status ~= nil then
  local ready = nil
  if obj.status.ready ~= nil then ready = obj.status.ready end
  if ready == nil and obj.status.conditions ~= nil then
    for i, c in ipairs(obj.status.conditions) do
      if c.type == "Ready" then ready = (c.status == "True") end
    end
  end
  if ready == true then
    hs.status = "Healthy"
    hs.message = "policy ready"
    return hs
  end
  if ready == false then
    hs.status = "Degraded"
    hs.message = "policy not ready"
    if obj.status.conditions ~= nil then
      for i, c in ipairs(obj.status.conditions) do
        if c.status ~= "True" and c.message ~= nil then hs.message = c.type .. ": " .. c.message end
      end
    end
    return hs
  end
end
hs.status = "Progressing"
hs.message = "policy status not reported yet"
return hs
