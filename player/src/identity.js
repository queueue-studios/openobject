'use strict';

// Host identity (HANDOFF §20, 2026-07-01; MAC-APP-PLAN §A3).
//
// A stable id and a friendly name for THIS Host, so a Display or Control client browsing the
// network can ask each Host "who are you?" and tell them apart. This is the identity the Bonjour
// advertisement (src/discovery.js) puts in its TXT records and that /api/identity returns.
//
//   • id   — a UUID generated once and PERSISTED in the settings table, so it survives restarts,
//            reboots, and self-updates. (This is the opposite of server.js's BOOT_ID, which is
//            deliberately fresh every process start to detect that a restart happened.)
//   • name — the friendly label shown in a Host picker. Persisted only once the owner customizes
//            it; until then it falls back to a sensible per-machine default, so an un-customized
//            name follows the machine's name if that changes. Context-aware (Matt, 2026-07-01):
//            the frame (Linux) is simply "OpenObject"; a Mac is "OpenObject on <computer name>",
//            self-disambiguating when someone runs both a frame and a Mac Host.
//
// Additive and off the playback path: nothing here touches rotation, display, or the frame's
// existing behavior.

const os = require('os');
const crypto = require('crypto');
const { execFileSync } = require('node:child_process');
const db = require('./db');

// The bare machine hostname, trimmed of any `.local` / domain suffix ("mac.local" → "mac").
function cleanHostname() {
  return (os.hostname() || '').replace(/\.local$/i, '').replace(/\..*$/, '').trim();
}

// macOS carries a human "Computer Name" (e.g. "Matt's MacBook Pro") separate from the network
// hostname; scutil reads it. Best-effort: any failure falls back to the plain hostname.
function macComputerName() {
  try {
    return execFileSync('scutil', ['--get', 'ComputerName'], { encoding: 'utf8', timeout: 2000 }).trim() || null;
  } catch {
    return null;
  }
}

// The default friendly name when the owner hasn't set one. Frame → "OpenObject"; anything else
// (a Mac, or any non-frame host) → "OpenObject on <machine>".
function defaultHostName() {
  // The frame (the Linux Host we ship) defaults to "OpenObject Frame" — descriptive and distinct
  // from the app name, so a client picker reads clearly ("OpenObject Frame" vs "OpenObject on <Mac>").
  // Owners with more than one frame can override this per-Host (host_name); this is only the default.
  if (process.platform === 'linux') return 'OpenObject Frame';
  const machine = (process.platform === 'darwin' && macComputerName()) || cleanHostname();
  return machine ? `OpenObject on ${machine}` : 'OpenObject';
}

// Stable id, generated once and persisted. Later reads return the same value.
function hostId() {
  let id = db.getSetting('host_id');
  if (!id) {
    id = crypto.randomUUID();
    db.setSetting('host_id', id);
  }
  return id;
}

// The friendly name: a custom one if the owner set it, else the per-machine default.
function hostName() {
  return db.getSetting('host_name') || defaultHostName();
}

// The full identity object shared by /api/identity, /healthz, and the Bonjour TXT records.
function identity() {
  return { id: hostId(), name: hostName() };
}

// This instance's DEVICE role (HANDOFF §17 Phase B). 'frame' when this is the shipped XXL frame
// appliance (the installer sets OO_ROLE=frame in the systemd unit); 'standalone' otherwise (a Mac,
// a Linux desktop, or a dev run). This is an EXPLICIT env, deliberately not platform-sniffing, so a
// Linux-desktop-as-display stays a standalone Host and never silently becomes a frame client. It is
// a different axis from /api/identity's architecture role ('host'), which every OpenObject server
// always is: the frame is still a full Host with its own Library; 'frame' only adds the Folder
// Collections client behavior (it SELECTS a Mac's shared folder instead of picking a local one).
function deviceRole() {
  return process.env.OO_ROLE === 'frame' ? 'frame' : 'standalone';
}

module.exports = { identity, hostId, hostName, defaultHostName, deviceRole };
