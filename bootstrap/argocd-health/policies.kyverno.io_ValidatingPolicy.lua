hs = {}
-- Kyverno ValidatingPolicy: ready(보고까지 가능)면 Healthy. admission 전용(background off)은 webhook만 구성되면 Healthy — 보고용 read(예: pods/exec)가 없어 ready=false여도 admission은 동작
if obj.status ~= nil and obj.status.conditionStatus ~= nil then
  local cs = obj.status.conditionStatus
  if cs.ready == true then
    hs.status = "Healthy"
    hs.message = "policy ready"
    return hs
  end
  local bg = true
  if obj.spec ~= nil and obj.spec.evaluation ~= nil and obj.spec.evaluation.background ~= nil and obj.spec.evaluation.background.enabled == false then bg = false end
  if cs.conditions ~= nil then
    for i, c in ipairs(cs.conditions) do
      if c.type == "WebhookConfigured" and c.status == "True" and bg == false then
        hs.status = "Healthy"
        hs.message = "admission-only policy, webhook configured"
        return hs
      end
    end
  end
  if cs.ready ~= nil then
    hs.status = "Degraded"
    hs.message = "policy not ready"
    if cs.conditions ~= nil then
      for i, c in ipairs(cs.conditions) do
        if c.status ~= "True" and c.message ~= nil then hs.message = c.type .. ": " .. c.message end
      end
    end
    return hs
  end
end
hs.status = "Progressing"
hs.message = "policy status not reported yet"
return hs
