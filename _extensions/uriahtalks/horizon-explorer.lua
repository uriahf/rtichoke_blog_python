local instance = 0

local function as_boolean(value)
  if value == nil then
    return false
  end
  value = string.lower(pandoc.utils.stringify(value))
  return value == "true" or value == "yes" or value == "1"
end

local function number_or(value, fallback)
  local parsed = tonumber(pandoc.utils.stringify(value or ""))
  return parsed or fallback
end

local function horizon_explorer(args, kwargs)
  instance = instance + 1

  local id = "uriah-horizon-explorer-" .. instance
  local competing_as_censored = as_boolean(kwargs["competing-as-censored"])
  local initial_horizon = number_or(kwargs["horizon"], 30)
  local minimum_horizon = number_or(kwargs["min"], 5)
  local maximum_horizon = number_or(kwargs["max"], 50)
  local step = number_or(kwargs["step"], 5)
  local title = pandoc.utils.stringify(kwargs["title"] or "Explore the horizon")
  local mode = competing_as_censored and "competing-as-censored" or "observed"

  local html = string.format([[
<div id="%s" class="uriah-horizon-explorer" data-mode="%s">
  <div class="uriah-horizon-heading">%s</div>
  <label class="uriah-horizon-control">
    <span>Fixed time horizon: <output>%g</output></span>
    <input type="range" min="%g" max="%g" step="%g" value="%g"
      aria-label="Fixed time horizon">
  </label>
  <div class="uriah-horizon-chart" role="img"
    aria-label="Follow-up timelines classified at the selected horizon"></div>
  <div class="uriah-horizon-key"></div>
</div>
<script>
(() => {
  const root = document.getElementById(%q);
  if (!root || root.dataset.ready === "true") return;
  root.dataset.ready = "true";

  const observations = [
    {id: 1, time: 24.1, outcome: "primary"},
    {id: 2, time: 9.7, outcome: "primary"},
    {id: 3, time: 49.9, outcome: "primary"},
    {id: 4, time: 18.6, outcome: "primary"},
    {id: 5, time: 34.8, outcome: "none"},
    {id: 6, time: 14.2, outcome: "competing"},
    {id: 7, time: 39.2, outcome: "primary"},
    {id: 8, time: 46.0, outcome: "competing"},
    {id: 9, time: 31.5, outcome: "none"},
    {id: 10, time: 4.3, outcome: "primary"}
  ];

  const states = {
    primary: {icon: "🤢", label: "Primary event"},
    competing: {icon: "💀", label: "Competing event"},
    censored: {icon: "🤬", label: "Censored"},
    nonEvent: {icon: "🤨", label: "Non-event through horizon"}
  };

  const input = root.querySelector("input");
  const output = root.querySelector("output");
  const chart = root.querySelector(".uriah-horizon-chart");
  const key = root.querySelector(".uriah-horizon-key");
  const maxTime = Number(input.max);
  const competingAsCensored = root.dataset.mode === "competing-as-censored";
  const ns = "http://www.w3.org/2000/svg";

  const classify = (d, horizon) => {
    if (d.time > horizon) return states.nonEvent;
    if (d.outcome === "primary") return states.primary;
    if (d.outcome === "competing") {
      return competingAsCensored ? states.censored : states.competing;
    }
    return states.censored;
  };

  const render = () => {
    const horizon = Number(input.value);
    output.value = horizon;
    chart.replaceChildren();

    const width = 900;
    const height = 390;
    const margin = {top: 22, right: 28, bottom: 48, left: 58};
    const innerWidth = width - margin.left - margin.right;
    const rowHeight = (height - margin.top - margin.bottom) / observations.length;
    const x = value => margin.left + (value / maxTime) * innerWidth;

    const svg = document.createElementNS(ns, "svg");
    svg.setAttribute("viewBox", `0 0 ${width} ${height}`);
    svg.setAttribute("class", "uriah-horizon-svg");

    for (let tick = 0; tick <= maxTime; tick += 10) {
      const tickLine = document.createElementNS(ns, "line");
      tickLine.setAttribute("x1", x(tick));
      tickLine.setAttribute("x2", x(tick));
      tickLine.setAttribute("y1", height - margin.bottom);
      tickLine.setAttribute("y2", height - margin.bottom + 6);
      tickLine.setAttribute("class", "uriah-axis");
      svg.appendChild(tickLine);

      const tickText = document.createElementNS(ns, "text");
      tickText.setAttribute("x", x(tick));
      tickText.setAttribute("y", height - margin.bottom + 24);
      tickText.setAttribute("class", "uriah-tick");
      tickText.textContent = tick;
      svg.appendChild(tickText);
    }

    const axisLabel = document.createElementNS(ns, "text");
    axisLabel.setAttribute("x", margin.left + innerWidth / 2);
    axisLabel.setAttribute("y", height - 5);
    axisLabel.setAttribute("class", "uriah-axis-label");
    axisLabel.textContent = "Follow-up time";
    svg.appendChild(axisLabel);

    const horizonLine = document.createElementNS(ns, "line");
    horizonLine.setAttribute("x1", x(horizon));
    horizonLine.setAttribute("x2", x(horizon));
    horizonLine.setAttribute("y1", margin.top - 8);
    horizonLine.setAttribute("y2", height - margin.bottom);
    horizonLine.setAttribute("class", "uriah-horizon-line");
    svg.appendChild(horizonLine);

    observations.forEach((d, index) => {
      const y = margin.top + rowHeight * (index + 0.5);
      const displayTime = Math.min(d.time, horizon);
      const state = classify(d, horizon);

      const label = document.createElementNS(ns, "text");
      label.setAttribute("x", margin.left - 14);
      label.setAttribute("y", y);
      label.setAttribute("class", "uriah-row-label");
      label.textContent = d.id;
      svg.appendChild(label);

      const followup = document.createElementNS(ns, "line");
      followup.setAttribute("x1", x(0));
      followup.setAttribute("x2", x(displayTime));
      followup.setAttribute("y1", y);
      followup.setAttribute("y2", y);
      followup.setAttribute("class", "uriah-followup-line");
      svg.appendChild(followup);

      const marker = document.createElementNS(ns, "text");
      marker.setAttribute("x", x(displayTime));
      marker.setAttribute("y", y);
      marker.setAttribute("class", "uriah-emoji-marker");
      marker.textContent = state.icon;
      const tooltip = document.createElementNS(ns, "title");
      tooltip.textContent = `Observation ${d.id}: ${state.label}; observed time ${d.time}`;
      marker.appendChild(tooltip);
      svg.appendChild(marker);
    });

    chart.appendChild(svg);

    const activeStates = competingAsCensored
      ? [states.primary, states.censored, states.nonEvent]
      : [states.primary, states.competing, states.censored, states.nonEvent];
    key.replaceChildren(...activeStates.map(state => {
      const item = document.createElement("span");
      item.innerHTML = `<span aria-hidden="true">${state.icon}</span> ${state.label}`;
      return item;
    }));
  };

  input.addEventListener("input", render);
  render();
})();
</script>
<style>
#%s.uriah-horizon-explorer {
  color: inherit;
  background: transparent;
  container-type: inline-size;
  margin: 1rem 0 1.5rem;
}
#%s .uriah-horizon-heading {
  font-weight: 650;
  font-size: 1.1em;
  margin-bottom: .65rem;
}
#%s .uriah-horizon-control { display: grid; gap: .3rem; max-width: 34rem; }
#%s input[type="range"] { width: 100%%; accent-color: #7a9a01; }
#%s .uriah-horizon-chart { width: 100%%; overflow-x: auto; background: transparent; }
#%s .uriah-horizon-svg { display: block; width: 100%%; min-width: 620px; background: transparent; }
#%s .uriah-axis { stroke: currentColor; stroke-width: 1; }
#%s .uriah-tick, #%s .uriah-axis-label, #%s .uriah-row-label {
  fill: currentColor; font: 14px Commissioner, system-ui, sans-serif;
}
#%s .uriah-tick, #%s .uriah-axis-label { text-anchor: middle; }
#%s .uriah-row-label { text-anchor: end; dominant-baseline: middle; }
#%s .uriah-followup-line { stroke: color-mix(in srgb, currentColor 38%%, transparent); stroke-width: 2; }
#%s .uriah-horizon-line { stroke: #7a9a01; stroke-width: 4; stroke-dasharray: 7 6; }
#%s .uriah-emoji-marker {
  font: 30px "Segoe UI Emoji", "Apple Color Emoji", sans-serif;
  text-anchor: middle; dominant-baseline: central; cursor: help;
}
#%s .uriah-horizon-key { display: flex; flex-wrap: wrap; gap: .45rem 1.1rem; font-size: .9em; }
@media (max-width: 650px) { #%s .uriah-horizon-svg { width: 720px; } }
</style>
]], id, mode, title, initial_horizon, minimum_horizon, maximum_horizon, step,
    initial_horizon, id, id, id, id, id, id, id, id, id, id, id, id, id, id,
    id, id, id, id, id, id)

  return pandoc.RawBlock("html", html)
end

return {
  ["horizon-explorer"] = horizon_explorer
}
