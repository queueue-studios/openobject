// OpenObject Wi-Fi setup, the phone half (HANDOFF §11). Served only while the frame is hosting its
// own network, so every request here goes to the frame at 192.168.4.1 (or openobject.local).
const $ = (id) => document.getElementById(id);
const select = $('network'), typed = $('networkTyped'), password = $('password');
const connectBtn = $('connect'), toggleBtn = $('toggleTyped'), errorEl = $('error');

let typing = false;   // typed entry is the fallback for a hidden network (§11)

function showError(msg) { errorEl.textContent = msg; errorEl.hidden = !msg; }

// The scanned list is the default because it is typo-proof. A network with no name is hidden and
// cannot be listed, which is exactly what the typed fallback is for.
async function loadNetworks() {
  try {
    const r = await fetch('/api/setup/networks');
    const { networks } = await r.json();
    if (!networks || !networks.length) {
      select.innerHTML = '<option value="">No networks found</option>';
      return;
    }
    select.innerHTML = networks.map((n) => `<option value="${encodeURIComponent(n.ssid)}">${n.ssid}</option>`).join('');
    // Decode on read rather than trusting the label, so an SSID containing markup cannot leak in.
    select.querySelectorAll('option').forEach((o, i) => { o.textContent = networks[i].ssid; });
  } catch {
    select.innerHTML = '<option value="">Could not scan</option>';
  }
}

function chosenSsid() {
  if (typing) return typed.value.trim();
  return decodeURIComponent(select.value || '');
}

toggleBtn.addEventListener('click', () => {
  typing = !typing;
  select.hidden = typing;
  typed.hidden = !typing;
  toggleBtn.textContent = typing ? 'Choose from the list instead' : 'Enter a network name instead';
  showError('');
  if (typing) typed.focus();
});

connectBtn.addEventListener('click', async () => {
  const ssid = chosenSsid();
  if (!ssid) return showError('Pick a network first.');
  connectBtn.disabled = true;
  showError('');
  try {
    const r = await fetch('/api/setup/connect', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ssid, password: password.value }),
    });
    const data = await r.json().catch(() => ({}));
    if (!r.ok) { connectBtn.disabled = false; return showError(data.error || 'That did not work.'); }
  } catch {
    // The frame may already be leaving its own network, which drops this request mid-flight. That is
    // the expected path, not an error: the frame confirms on its own screen (§11).
  }
  $('form').hidden = true;
  $('applying').hidden = false;
});

loadNetworks();
