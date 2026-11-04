/**
 * SPIDER MIND | PROJECT SPIDER
 * Full-featured Web Application & 3D Web Engine
 */

// ============================================================================
// State & Configuration
// ============================================================================

const API_BASE = '/api/v1';
const CLIENT_ID = 'web_' + Math.random().toString(36).substring(2, 10);

const state = {
  user: null,
  accessToken: localStorage.getItem('spider_access_token') || null,
  refreshToken: localStorage.getItem('spider_refresh_token') || null,
  spaces: [],
  threads: [],
  activity: [],
  insights: null,
  activeTab: 'viewWeb',
  activeSpaceFilter: null,
  activeTypeFilter: 'all',
  activeStatusFilter: 'open',
  searchKeyword: '',
  selectedThreadId: null,
  flashThreadIds: new Set(),
  socket: null,
  connected: false,
  reduceMotion: false,
};

// ============================================================================
// Web Audio Reminder Synthesizer
// ============================================================================

const audioCtx = new (window.AudioContext || window.webkitAudioContext)();

function playReminderChime() {
  try {
    if (audioCtx.state === 'suspended') {
      audioCtx.resume();
    }
    const now = audioCtx.currentTime;
    
    // Smooth dual-tone glass harp chime
    const osc1 = audioCtx.createOscillator();
    const osc2 = audioCtx.createOscillator();
    const gainNode = audioCtx.createGain();

    osc1.type = 'sine';
    osc1.frequency.setValueAtTime(587.33, now); // D5
    osc1.frequency.exponentialRampToValueAtTime(880, now + 0.15); // A5

    osc2.type = 'triangle';
    osc2.frequency.setValueAtTime(880, now);
    osc2.frequency.exponentialRampToValueAtTime(1174.66, now + 0.2); // D6

    gainNode.gain.setValueAtTime(0.3, now);
    gainNode.gain.exponentialRampToValueAtTime(0.001, now + 1.2);

    osc1.connect(gainNode);
    osc2.connect(gainNode);
    gainNode.connect(audioCtx.destination);

    osc1.start(now);
    osc2.start(now);
    osc1.stop(now + 1.2);
    osc2.stop(now + 1.2);
  } catch (e) {
    console.warn('Audio chime could not play:', e);
  }
}

// ============================================================================
// Notification Toasts
// ============================================================================

function showToast(message, type = 'info', action = null) {
  const container = document.getElementById('toastContainer');
  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;

  const icon = type === 'reminder' ? '🔔' : type === 'success' ? '✓' : type === 'error' ? '⚠️' : 'ℹ️';
  toast.innerHTML = `
    <span class="toast-icon">${icon}</span>
    <span class="toast-msg">${message}</span>
  `;

  if (action) {
    const actionBtn = document.createElement('button');
    actionBtn.className = 'toast-undo-btn';
    actionBtn.textContent = action.label;
    actionBtn.onclick = () => {
      action.callback();
      toast.remove();
    };
    toast.appendChild(actionBtn);
  }

  container.appendChild(toast);
  setTimeout(() => {
    toast.style.opacity = '0';
    toast.style.transform = 'translateY(-10px)';
    setTimeout(() => toast.remove(), 300);
  }, 4500);
}

// ============================================================================
// API Client with Automatic Refresh
// ============================================================================

async function apiRequest(endpoint, options = {}) {
  const headers = {
    'Content-Type': 'application/json',
    'X-Client-Id': CLIENT_ID,
    ...(options.headers || {}),
  };

  if (state.accessToken) {
    headers['Authorization'] = `Bearer ${state.accessToken}`;
  }

  let response = await fetch(`${API_BASE}${endpoint}`, {
    ...options,
    headers,
  });

  // Handle 401: Token expired, attempt refresh
  if (response.status === 401 && state.refreshToken && !endpoint.includes('/auth/')) {
    const refreshed = await refreshAuthToken();
    if (refreshed) {
      headers['Authorization'] = `Bearer ${state.accessToken}`;
      response = await fetch(`${API_BASE}${endpoint}`, {
        ...options,
        headers,
      });
    } else {
      showAuthModal(true);
      throw new Error('Authentication expired. Please sign in again.');
    }
  }

  if (response.status === 204) return null;

  const data = await response.json();
  if (!response.ok) {
    throw new Error(data.error?.message || 'API request failed');
  }
  return data;
}

async function refreshAuthToken() {
  try {
    const res = await fetch(`${API_BASE}/auth/refresh`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ refreshToken: state.refreshToken }),
    });
    if (!res.ok) return false;
    const data = await res.json();
    setSession(data.accessToken, data.refreshToken);
    return true;
  } catch {
    return false;
  }
}

function setSession(accessToken, refreshToken) {
  state.accessToken = accessToken;
  state.refreshToken = refreshToken;
  if (accessToken) localStorage.setItem('spider_access_token', accessToken);
  else localStorage.removeItem('spider_access_token');
  if (refreshToken) localStorage.setItem('spider_refresh_token', refreshToken);
  else localStorage.removeItem('spider_refresh_token');
}

// ============================================================================
// Realtime Socket.IO Connection
// ============================================================================

function initRealtime() {
  if (state.socket) {
    state.socket.disconnect();
  }

  if (!state.accessToken) return;

  const socket = io({
    auth: { token: state.accessToken },
    transports: ['websocket', 'polling'],
  });

  state.socket = socket;

  socket.on('connect', () => {
    state.connected = true;
    updateConnectionStatus(true);
  });

  socket.on('disconnect', () => {
    state.connected = false;
    updateConnectionStatus(false);
  });

  socket.on('connect_error', async (err) => {
    if (err.message === 'unauthorized') {
      const refreshed = await refreshAuthToken();
      if (refreshed) {
        socket.auth.token = state.accessToken;
        socket.connect();
      }
    }
  });

  // Realtime updates
  socket.on('thread:upsert', (payload) => {
    if (payload.origin === CLIENT_ID) return;
    const thread = payload.thread;
    upsertLocalThread(thread);
    triggerThreadFlash(thread.id);
    renderAllViews();
  });

  socket.on('thread:delete', (payload) => {
    if (payload.origin === CLIENT_ID) return;
    removeLocalThread(payload.id);
    renderAllViews();
  });

  socket.on('space:upsert', (payload) => {
    if (payload.origin === CLIENT_ID) return;
    const space = payload.space;
    const idx = state.spaces.findIndex((s) => s.id === space.id);
    if (idx >= 0) state.spaces[idx] = space;
    else state.spaces.push(space);
    renderSpaceFilters();
    renderAllViews();
  });

  socket.on('space:delete', (payload) => {
    if (payload.origin === CLIENT_ID) return;
    state.spaces = state.spaces.filter((s) => s.id !== payload.id);
    renderSpaceFilters();
    renderAllViews();
  });

  socket.on('reminder:due', (payload) => {
    playReminderChime();
    showToast(`🔔 Reminder Due: "${payload.title}"`, 'reminder', {
      label: 'Open',
      callback: () => openThreadModal(payload.threadId),
    });
  });

  socket.on('activity:new', (payload) => {
    state.activity.unshift(payload.activity);
    if (state.activity.length > 50) state.activity.pop();
    renderActivityFeed();
  });
}

function updateConnectionStatus(isLive) {
  const pill = document.getElementById('connectionPill');
  if (isLive) {
    pill.className = 'status-pill status-live';
    pill.querySelector('.status-label').textContent = 'LIVE';
  } else {
    pill.className = 'status-pill status-offline';
    pill.querySelector('.status-label').textContent = 'OFFLINE';
  }
}

function triggerThreadFlash(id) {
  state.flashThreadIds.add(id);
  setTimeout(() => {
    state.flashThreadIds.delete(id);
  }, 2500);
}

function upsertLocalThread(thread) {
  const idx = state.threads.findIndex((t) => t.id === thread.id);
  if (idx >= 0) state.threads[idx] = thread;
  else state.threads.push(thread);
}

function removeLocalThread(id) {
  state.threads = state.threads.filter((t) => t.id !== id);
}

// ============================================================================
// Data Loading & Sync
// ============================================================================

async function loadInitialData() {
  try {
    const userRes = await apiRequest('/me');
    state.user = userRes.user;
    updateUserUI();

    const [spacesRes, threadsRes, activityRes, insightsRes] = await Promise.all([
      apiRequest('/spaces'),
      apiRequest('/threads'),
      apiRequest('/activity?limit=30'),
      apiRequest('/insights'),
    ]);

    state.spaces = spacesRes.spaces || [];
    state.threads = threadsRes.threads || [];
    state.activity = activityRes.activity || [];
    state.insights = insightsRes;

    renderSpaceFilters();
    renderAllViews();
    initRealtime();
    webEngine.fit();
  } catch (err) {
    console.error('Initialization error:', err);
    showAuthModal(true);
  }
}

function updateUserUI() {
  if (!state.user) return;
  const avatarText = document.getElementById('userAvatarText');
  avatarText.textContent = (state.user.name || state.user.email || 'U')[0].toUpperCase();

  const nameInput = document.getElementById('settingName');
  const emailInput = document.getElementById('settingEmail');
  const tzInput = document.getElementById('settingTimezone');
  if (nameInput) nameInput.value = state.user.name || '';
  if (emailInput) emailInput.value = state.user.email || '';
  if (tzInput) tzInput.value = state.user.timezone || 'UTC';
}

// ============================================================================
// 3D Spider Web Perspective Canvas Engine
// ============================================================================

class WebMetrics {
  static slotGap = 1.25;
  static rowGap = 1.25;
  static bandGap = 2.1;
  static minInnerRadius = 4.0;
  static zStep = 0.8;
  static rowSize = 3;
}

class WebCamera {
  constructor() {
    this.width = 1;
    this.height = 1;
    this.yaw = 0;
    this.pitch = 0.87; // default ~50 deg tilt
    this.distance = 28;
    this.panX = 0;
    this.panY = 0;
    this.tYaw = 0;
    this.tPitch = 0.87;
    this.tDistance = 28;
    this.tPanX = 0;
    this.tPanY = 0;
    this.fitDistance = 28;
  }

  get focal() {
    return Math.min(this.width, this.height) * 1.1;
  }

  project(x, y, z) {
    const dx = x - this.panX;
    const dy = y - this.panY;
    const cy = Math.cos(this.yaw);
    const sy = Math.sin(this.yaw);
    const x1 = dx * cy - dy * sy;
    const y1 = dx * sy + dy * cy;
    const cp = Math.cos(this.pitch);
    const sp = Math.sin(this.pitch);
    const up = y1 * cp + z * sp;
    const toward = z * cp - y1 * sp;
    const zc = this.distance - toward;

    if (zc < 0.5) return { x: this.width / 2, y: this.height / 2, scale: 0, depth: zc, visible: false };
    const s = this.focal / zc;
    return {
      x: this.width / 2 + x1 * s,
      y: this.height / 2 - up * s,
      scale: s,
      depth: zc,
      visible: true,
    };
  }

  fit(radius = 16) {
    const r = Math.max(radius, 4.0) * 1.15;
    const cp = Math.cos(0.87);
    const sx = (0.46 * this.width) / r;
    const sy = (0.46 * this.height) / (r * Math.max(cp, 0.35) + r * 0.25);
    const s = Math.max(Math.min(sx, sy), 1e-3);
    const d = Math.max(this.focal / s, r * 1.8);
    this.fitDistance = d;
    this.tDistance = d;
    this.tPitch = 0.87;
    this.tPanX = 0;
    this.tPanY = 0;
  }

  update() {
    const damp = state.reduceMotion ? 1 : 0.14;
    this.yaw += (this.tYaw - this.yaw) * damp;
    this.pitch += (this.tPitch - this.pitch) * damp;
    this.distance += (this.tDistance - this.distance) * damp;
    this.panX += (this.tPanX - this.panX) * damp;
    this.panY += (this.tPanY - this.panY) * damp;
  }
}

class Web3DEngine {
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.camera = new WebCamera();
    this.layoutNodes = [];
    this.spokes = [];
    this.rings = [];
    this.particles = [];
    this.isDragging = false;
    this.isPanning = false;
    this.lastMouse = { x: 0, y: 0 };
    this.animFrame = null;
    this.time = 0;

    this.initEvents();
    this.resize();
  }

  resize() {
    const rect = this.canvas.parentElement.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    this.canvas.width = rect.width * dpr;
    this.canvas.height = rect.height * dpr;
    this.ctx.scale(dpr, dpr);
    this.camera.width = rect.width;
    this.camera.height = rect.height;
  }

  initEvents() {
    window.addEventListener('resize', () => this.resize());

    this.canvas.addEventListener('mousedown', (e) => {
      this.isDragging = true;
      this.isPanning = e.button === 2 || e.shiftKey;
      this.lastMouse = { x: e.clientX, y: e.clientY };
    });

    window.addEventListener('mousemove', (e) => {
      if (!this.isDragging) return;
      const dx = e.clientX - this.lastMouse.x;
      const dy = e.clientY - this.lastMouse.y;
      this.lastMouse = { x: e.clientX, y: e.clientY };

      if (this.isPanning) {
        const factor = this.camera.distance / (this.camera.focal * 1.5);
        this.camera.tPanX -= dx * factor;
        this.camera.tPanY += dy * factor;
      } else {
        this.camera.tYaw += dx * 0.007;
        this.camera.tPitch = Math.max(0.12, Math.min(1.45, this.camera.tPitch + dy * 0.007));
      }
    });

    window.addEventListener('mouseup', () => {
      this.isDragging = false;
      this.isPanning = false;
    });

    this.canvas.addEventListener('wheel', (e) => {
      e.preventDefault();
      const zoomFactor = e.deltaY > 0 ? 1.08 : 0.92;
      this.camera.tDistance = Math.max(4, Math.min(120, this.camera.tDistance * zoomFactor));
    }, { passive: false });

    this.canvas.addEventListener('dblclick', () => {
      this.fit();
    });

    this.canvas.addEventListener('click', (e) => {
      const rect = this.canvas.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;
      this.handleNodeClick(x, y);
    });

    this.canvas.addEventListener('contextmenu', (e) => e.preventDefault());
  }

  handleNodeClick(screenX, screenY) {
    let nearestNode = null;
    let nearestDist = 28; // 28px tap radius

    for (const node of this.layoutNodes) {
      if (!node.proj || !node.proj.visible) continue;
      const dist = Math.hypot(node.proj.x - screenX, node.proj.y - screenY);
      if (dist < nearestDist) {
        nearestDist = dist;
        nearestNode = node;
      }
    }

    if (nearestNode) {
      selectThread(nearestNode.thread.id);
    } else {
      selectThread(null);
    }
  }

  computeLayout() {
    const spaces = state.spaces.length > 0 ? state.spaces : [
      { id: 'work', name: 'Work', color: '#32B4FF' },
      { id: 'study', name: 'Study', color: '#3DDC97' },
      { id: 'personal', name: 'Personal', color: '#FF2A44' },
    ];

    const S = spaces.length;
    this.spokes = spaces.map((sp, i) => ({
      spaceId: sp.id,
      name: sp.name,
      color: sp.color || '#32B4FF',
      angle: -Math.PI / 2 + (2 * Math.PI * i) / S,
      index: i,
    }));

    // Group threads into cells (space, urgency band)
    // Urgency bands: now, week, month, later, done
    const bands = ['now', 'week', 'month', 'later', 'done'];
    const nowTs = Date.now();

    const getBand = (thread) => {
      if (thread.status === 'done') return 'done';
      if (!thread.dueAt) return 'later';
      const due = new Date(thread.dueAt).getTime();
      const diffHours = (due - nowTs) / (1000 * 3600);
      if (diffHours <= 24) return 'now';
      if (diffHours <= 24 * 7) return 'week';
      if (diffHours <= 24 * 30) return 'month';
      return 'later';
    };

    let currentRadius = WebMetrics.minInnerRadius;
    this.rings = [];

    // Calculate ring radiuses
    for (const band of bands) {
      const ringRadius = currentRadius;
      const threadsInBand = state.threads.filter((t) => getBand(t) === band);
      const rows = Math.max(1, Math.ceil(threadsInBand.length / (S * WebMetrics.rowSize)));
      const extent = ringRadius + (rows - 1) * WebMetrics.rowGap;
      this.rings.push({ band, radius: ringRadius, extent, rows });
      currentRadius = extent + WebMetrics.bandGap;
    }

    // Position each thread deterministically
    this.layoutNodes = [];
    const priorityIndex = { low: 0, medium: 1, high: 2 };

    for (const spoke of this.spokes) {
      for (const ring of this.rings) {
        const cellThreads = state.threads.filter(
          (t) => (t.spaceId === spoke.spaceId || (spoke.index === 0 && !t.spaceId)) && getBand(t) === ring.band
        );

        // Sort: high priority first, then due date
        cellThreads.sort((a, b) => {
          const pa = priorityIndex[a.priority] ?? 1;
          const pb = priorityIndex[b.priority] ?? 1;
          if (pb !== pa) return pb - pa;
          return (a.dueAt ? new Date(a.dueAt) : 9e14) - (b.dueAt ? new Date(b.dueAt) : 9e14);
        });

        cellThreads.forEach((thread, i) => {
          const row = Math.floor(i / WebMetrics.rowSize);
          const col = i % WebMetrics.rowSize;
          const r = ring.radius + row * WebMetrics.rowGap;

          // Angular spread within the wedge
          const spread = (Math.PI / S) * 0.65;
          const offsetAngle = cellThreads.length === 1 ? 0 : (col - 1) * (spread / 2);
          const angle = spoke.angle + offsetAngle;

          const wx = r * Math.cos(angle);
          const wy = -r * Math.sin(angle); // Upwards is positive in world space
          const pIdx = priorityIndex[thread.priority] ?? 1;
          const wz = (pIdx - 1) * WebMetrics.zStep;

          this.layoutNodes.push({
            thread,
            spoke,
            ring,
            world: { x: wx, y: wy, z: wz },
            proj: null,
          });
        });
      }
    }
  }

  fit() {
    let maxR = 12;
    for (const ring of this.rings) {
      if (ring.extent > maxR) maxR = ring.extent;
    }
    this.camera.fit(maxR);
  }

  start() {
    const loop = (timestamp) => {
      this.time = timestamp * 0.001;
      this.camera.update();
      this.render();
      this.animFrame = requestAnimationFrame(loop);
    };
    this.animFrame = requestAnimationFrame(loop);
  }

  render() {
    const ctx = this.ctx;
    const w = this.camera.width;
    const h = this.camera.height;

    ctx.clearRect(0, 0, w, h);

    // Dynamic background grid web & fog
    ctx.save();

    // 1. Project all nodes
    for (const node of this.layoutNodes) {
      node.proj = this.camera.project(node.world.x, node.world.y, node.world.z);
    }

    // 2. Draw Spokes (Radial Web Strands from center)
    for (const spoke of this.spokes) {
      const outerR = this.rings.length > 0 ? this.rings[this.rings.length - 1].extent + 2 : 24;
      const p0 = this.camera.project(0, 0, 0);
      const p1 = this.camera.project(outerR * Math.cos(spoke.angle), -outerR * Math.sin(spoke.angle), 0);

      if (p0.visible && p1.visible) {
        ctx.beginPath();
        ctx.moveTo(p0.x, p0.y);
        ctx.lineTo(p1.x, p1.y);
        ctx.strokeStyle = spoke.color;
        ctx.globalAlpha = 0.22;
        ctx.lineWidth = 1.2;
        ctx.stroke();

        // Spoke label
        const lp = this.camera.project((outerR + 1.8) * Math.cos(spoke.angle), -(outerR + 1.8) * Math.sin(spoke.angle), 0);
        if (lp.visible) {
          ctx.font = '600 11px Outfit, sans-serif';
          ctx.fillStyle = spoke.color;
          ctx.globalAlpha = 0.85;
          ctx.textAlign = 'center';
          ctx.textBaseline = 'middle';
          ctx.fillText(spoke.name.toUpperCase(), lp.x, lp.y);
        }
      }
    }

    // 3. Draw Urgency Rings (Polygonal web rings)
    const S = this.spokes.length;
    for (const ring of this.rings) {
      ctx.beginPath();
      let first = true;
      for (let i = 0; i < S; i++) {
        const angle = this.spokes[i].angle;
        const pt = this.camera.project(ring.radius * Math.cos(angle), -ring.radius * Math.sin(angle), 0);
        if (pt.visible) {
          if (first) {
            ctx.moveTo(pt.x, pt.y);
            first = false;
          } else {
            ctx.lineTo(pt.x, pt.y);
          }
        }
      }
      ctx.closePath();
      ctx.strokeStyle = '#32B4FF';
      ctx.globalAlpha = 0.12;
      ctx.lineWidth = 1;
      ctx.setLineDash([3, 4]);
      ctx.stroke();
      ctx.setLineDash([]);
    }

    // 4. Draw Inter-thread Strands (Explicit & Keyword Silk Strands)
    const selectedId = state.selectedThreadId;
    const filterSpace = state.activeSpaceFilter;
    const search = state.searchKeyword.toLowerCase().trim();

    for (let i = 0; i < this.layoutNodes.length; i++) {
      const n1 = this.layoutNodes[i];
      if (!n1.proj || !n1.proj.visible) continue;

      for (let j = i + 1; j < this.layoutNodes.length; j++) {
        const n2 = this.layoutNodes[j];
        if (!n2.proj || !n2.proj.visible) continue;

        const isExplicitLink =
          (n1.thread.links && n1.thread.links.includes(n2.thread.id)) ||
          (n2.thread.links && n2.thread.links.includes(n1.thread.id));

        const sharedKeyword =
          n1.thread.keywords &&
          n2.thread.keywords &&
          n1.thread.keywords.some((k) => n2.thread.keywords.includes(k));

        if (!isExplicitLink && !sharedKeyword) continue;

        const isConnectedToSelected = selectedId && (n1.thread.id === selectedId || n2.thread.id === selectedId);

        ctx.beginPath();
        // Slight curve for spider-silk feel
        const mx = (n1.proj.x + n2.proj.x) / 2;
        const my = (n1.proj.y + n2.proj.y) / 2 + Math.sin(this.time * 2 + i) * 3;
        ctx.moveTo(n1.proj.x, n1.proj.y);
        ctx.quadraticCurveTo(mx, my, n2.proj.x, n2.proj.y);

        if (isExplicitLink) {
          ctx.strokeStyle = isConnectedToSelected ? '#32B4FF' : '#7dd3fc';
          ctx.globalAlpha = isConnectedToSelected ? 0.9 : 0.35;
          ctx.lineWidth = isConnectedToSelected ? 2.4 : 1.2;
          ctx.stroke();
        } else {
          ctx.strokeStyle = '#3DDC97';
          ctx.globalAlpha = isConnectedToSelected ? 0.75 : 0.2;
          ctx.lineWidth = 1;
          ctx.setLineDash([2, 3]);
          ctx.stroke();
          ctx.setLineDash([]);
        }

        // Flowing particles along strands connected to selected thread
        if (isConnectedToSelected && !state.reduceMotion) {
          const tProgress = (this.time * 0.8 + (i % 3) * 0.33) % 1;
          const px = (1 - tProgress) * (1 - tProgress) * n1.proj.x + 2 * (1 - tProgress) * tProgress * mx + tProgress * tProgress * n2.proj.x;
          const py = (1 - tProgress) * (1 - tProgress) * n1.proj.y + 2 * (1 - tProgress) * tProgress * my + tProgress * tProgress * n2.proj.y;

          ctx.beginPath();
          ctx.arc(px, py, 2.5, 0, Math.PI * 2);
          ctx.fillStyle = '#fff';
          ctx.globalAlpha = 0.95;
          ctx.fill();
        }
      }
    }

    // 5. Draw Thread Nodes (Sorted back-to-front by depth for proper layering)
    const sortedNodes = [...this.layoutNodes].sort((a, b) => (b.proj?.depth || 0) - (a.proj?.depth || 0));

    for (const node of sortedNodes) {
      if (!node.proj || !node.proj.visible) continue;

      const { x, y, scale } = node.proj;
      const th = node.thread;
      const color = node.spoke.color || '#32B4FF';

      // Filters & Search Dimming
      let dimmed = false;
      if (filterSpace && th.spaceId !== filterSpace) dimmed = true;
      if (search) {
        const matches =
          th.title.toLowerCase().includes(search) ||
          (th.tags && th.tags.some((t) => t.toLowerCase().includes(search))) ||
          (th.keywords && th.keywords.some((k) => k.toLowerCase().includes(search)));
        if (!matches) dimmed = true;
      }
      if (selectedId && th.id !== selectedId) {
        const isConnected =
          th.links?.includes(selectedId) ||
          state.threads.find((t) => t.id === selectedId)?.links?.includes(th.id);
        if (!isConnected) dimmed = true;
      }

      ctx.save();
      ctx.globalAlpha = dimmed ? 0.25 : 1.0;

      const baseR = Math.max(7, Math.min(22, 10 * (scale / 22)));
      const isSelected = th.id === selectedId;
      const isFlashing = state.flashThreadIds.has(th.id);

      // Overdue Pulsing Halo
      const isOverdue = th.dueAt && new Date(th.dueAt).getTime() < Date.now() && th.status !== 'done';
      if (isOverdue && !dimmed) {
        const pulse = 1 + Math.sin(this.time * 5) * 0.25;
        ctx.beginPath();
        ctx.arc(x, y, baseR * 1.8 * pulse, 0, Math.PI * 2);
        ctx.strokeStyle = '#FF2A44';
        ctx.globalAlpha = 0.4;
        ctx.lineWidth = 2;
        ctx.stroke();
      }

      // Live Update Ripple
      if (isFlashing && !state.reduceMotion) {
        const rip = (this.time * 2) % 1;
        ctx.beginPath();
        ctx.arc(x, y, baseR * (1 + rip * 2), 0, Math.PI * 2);
        ctx.strokeStyle = '#32B4FF';
        ctx.globalAlpha = 1 - rip;
        ctx.lineWidth = 2;
        ctx.stroke();
      }

      // Node Geometry based on Type
      // task: circle, idea: diamond, question: hexagon, goal: star
      this.drawNodeShape(ctx, x, y, baseR, th.type, color, th.status);

      // Selected Double Ring
      if (isSelected) {
        ctx.beginPath();
        ctx.arc(x, y, baseR + 5, 0, Math.PI * 2);
        ctx.strokeStyle = '#fff';
        ctx.lineWidth = 2;
        ctx.globalAlpha = 0.9;
        ctx.stroke();
      }

      // Title Label
      if (scale > 14 && !dimmed) {
        ctx.font = '500 11px Outfit, sans-serif';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'top';
        ctx.fillStyle = '#f8fafc';
        ctx.globalAlpha = isSelected ? 1 : 0.85;

        // Truncate long titles
        const text = th.title.length > 20 ? th.title.slice(0, 18) + '…' : th.title;
        ctx.fillText(text, x, y + baseR + 4);
      }

      ctx.restore();
    }

    ctx.restore();
  }

  drawNodeShape(ctx, x, y, r, type, color, status) {
    ctx.beginPath();

    if (type === 'idea') {
      // Diamond
      ctx.moveTo(x, y - r);
      ctx.lineTo(x + r, y);
      ctx.lineTo(x, y + r);
      ctx.lineTo(x - r, y);
      ctx.closePath();
    } else if (type === 'question') {
      // Hexagon
      for (let i = 0; i < 6; i++) {
        const a = (i * Math.PI) / 3;
        const px = x + r * Math.cos(a);
        const py = y + r * Math.sin(a);
        if (i === 0) ctx.moveTo(px, py);
        else ctx.lineTo(px, py);
      }
      ctx.closePath();
    } else if (type === 'goal') {
      // 5-Point Star
      for (let i = 0; i < 10; i++) {
        const rad = i % 2 === 0 ? r * 1.15 : r * 0.55;
        const a = (i * Math.PI) / 5 - Math.PI / 2;
        const px = x + rad * Math.cos(a);
        const py = y + rad * Math.sin(a);
        if (i === 0) ctx.moveTo(px, py);
        else ctx.lineTo(px, py);
      }
      ctx.closePath();
    } else {
      // Task: Circle
      ctx.arc(x, y, r, 0, Math.PI * 2);
    }

    if (status === 'done') {
      ctx.fillStyle = 'rgba(255, 255, 255, 0.15)';
      ctx.fill();
      ctx.strokeStyle = color;
      ctx.lineWidth = 1.5;
      ctx.stroke();

      // Checkmark tick
      ctx.beginPath();
      ctx.moveTo(x - r * 0.35, y);
      ctx.lineTo(x - r * 0.05, y + r * 0.35);
      ctx.lineTo(x + r * 0.45, y - r * 0.35);
      ctx.strokeStyle = '#fff';
      ctx.lineWidth = 2;
      ctx.stroke();
    } else if (status === 'doing') {
      ctx.fillStyle = color;
      ctx.fill();
      ctx.strokeStyle = '#fff';
      ctx.lineWidth = 2;
      ctx.stroke();

      // Rotating progress arc around doing items
      if (!state.reduceMotion) {
        ctx.beginPath();
        const startA = this.time * 4;
        ctx.arc(x, y, r + 3, startA, startA + Math.PI * 0.7);
        ctx.strokeStyle = '#fff';
        ctx.lineWidth = 2;
        ctx.stroke();
      }
    } else {
      // Todo
      ctx.fillStyle = 'rgba(10, 16, 32, 0.8)';
      ctx.fill();
      ctx.strokeStyle = color;
      ctx.lineWidth = 2;
      ctx.stroke();
    }
  }
}

// Global engine instance
let webEngine = null;

// ============================================================================
// View Switcher & Navigation
// ============================================================================

function setupNavigation() {
  const tabs = document.querySelectorAll('.nav-tab');
  tabs.forEach((tab) => {
    tab.addEventListener('click', () => {
      const targetId = tab.dataset.tab;
      switchTab(targetId);
    });
  });

  // Top header button shortcuts
  document.getElementById('legendBtn').addEventListener('click', () => {
    document.getElementById('legendModal').classList.remove('hidden');
  });

  document.getElementById('closeLegendModalBtn').addEventListener('click', () => {
    document.getElementById('legendModal').classList.add('hidden');
  });

  document.getElementById('gotItLegendBtn').addEventListener('click', () => {
    document.getElementById('legendModal').classList.add('hidden');
  });

  document.getElementById('recenterBtn').addEventListener('click', () => {
    webEngine.fit();
  });

  document.getElementById('newThreadBtn').addEventListener('click', () => {
    openThreadModal();
  });

  document.getElementById('keywordSearch').addEventListener('input', (e) => {
    state.searchKeyword = e.target.value;
    document.getElementById('clearSearchBtn').classList.toggle('hidden', !e.target.value);
    if (state.activeTab === 'viewThreads') renderThreadsListView();
  });

  document.getElementById('clearSearchBtn').addEventListener('click', () => {
    document.getElementById('keywordSearch').value = '';
    state.searchKeyword = '';
    document.getElementById('clearSearchBtn').classList.add('hidden');
    if (state.activeTab === 'viewThreads') renderThreadsListView();
  });

  document.getElementById('userProfileBtn').addEventListener('click', () => {
    switchTab('viewSettings');
  });
}

function switchTab(tabId) {
  state.activeTab = tabId;
  document.querySelectorAll('.nav-tab').forEach((t) => {
    t.classList.toggle('active', t.dataset.tab === tabId);
  });
  document.querySelectorAll('.view-panel').forEach((p) => {
    p.classList.toggle('active', p.id === tabId);
  });

  if (tabId === 'viewWeb') {
    webEngine.resize();
  } else if (tabId === 'viewThreads') {
    renderThreadsListView();
  } else if (tabId === 'viewInsights') {
    renderInsightsView();
  } else if (tabId === 'viewSettings') {
    renderSettingsView();
  }
}

function renderAllViews() {
  webEngine.computeLayout();
  renderThreadsListView();
  renderInsightsView();
  renderSettingsView();
}

// ============================================================================
// Space Filters Bar
// ============================================================================

function renderSpaceFilters() {
  const container = document.getElementById('spaceFilters');
  container.innerHTML = '';

  const allChip = document.createElement('button');
  allChip.className = `space-chip ${state.activeSpaceFilter === null ? 'active' : ''}`;
  allChip.innerHTML = `<span>All Spaces</span>`;
  allChip.onclick = () => {
    state.activeSpaceFilter = null;
    renderSpaceFilters();
    if (state.activeTab === 'viewThreads') renderThreadsListView();
  };
  container.appendChild(allChip);

  state.spaces.forEach((space) => {
    const chip = document.createElement('button');
    chip.className = `space-chip ${state.activeSpaceFilter === space.id ? 'active' : ''}`;
    chip.style.setProperty('--chip-color', space.color);
    chip.innerHTML = `
      <span class="space-chip-dot" style="background:${space.color}"></span>
      <span>${space.name}</span>
    `;
    chip.onclick = () => {
      state.activeSpaceFilter = state.activeSpaceFilter === space.id ? null : space.id;
      renderSpaceFilters();
      if (state.activeTab === 'viewThreads') renderThreadsListView();
    };
    container.appendChild(chip);
  });
}

// ============================================================================
// Selected Thread Floating Card
// ============================================================================

function selectThread(threadId) {
  state.selectedThreadId = threadId;
  const card = document.getElementById('threadFloatCard');

  if (!threadId) {
    card.classList.add('hidden');
    return;
  }

  const thread = state.threads.find((t) => t.id === threadId);
  if (!thread) {
    card.classList.add('hidden');
    return;
  }

  const space = state.spaces.find((s) => s.id === thread.spaceId);
  document.getElementById('floatCardSpace').textContent = space?.name || 'General';
  document.getElementById('floatCardSpace').style.color = space?.color || '#32B4FF';
  document.getElementById('floatCardType').textContent = thread.type.toUpperCase();

  const priorityBadge = document.getElementById('floatCardPriority');
  priorityBadge.textContent = thread.priority.toUpperCase();
  priorityBadge.className = `priority-badge ${thread.priority === 'high' ? 'priority-high' : ''}`;

  document.getElementById('floatCardTitle').textContent = thread.title;
  document.getElementById('floatCardNotes').textContent = thread.notes || 'No extra notes provided.';

  // Meta
  const dueBadge = document.getElementById('floatCardDue');
  if (thread.dueAt) {
    const isOverdue = new Date(thread.dueAt) < new Date() && thread.status !== 'done';
    dueBadge.textContent = `📅 ${new Date(thread.dueAt).toLocaleDateString([], { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })}`;
    dueBadge.className = `due-badge ${isOverdue ? 'due-overdue' : ''}`;
    dueBadge.classList.remove('hidden');
  } else {
    dueBadge.classList.add('hidden');
  }

  const checklistBadge = document.getElementById('floatCardChecklist');
  if (thread.checklist && thread.checklist.length > 0) {
    const doneCount = thread.checklist.filter((c) => c.done).length;
    checklistBadge.textContent = `✓ ${doneCount}/${thread.checklist.length}`;
    checklistBadge.classList.remove('hidden');
  } else {
    checklistBadge.classList.add('hidden');
  }

  // Quick Action Buttons
  const toggleBtn = document.getElementById('floatCardToggleStatus');
  toggleBtn.textContent = thread.status === 'doing' ? 'Set Todo' : 'Start (Doing)';
  toggleBtn.onclick = () => {
    quickUpdateThreadStatus(thread.id, thread.status === 'doing' ? 'todo' : 'doing');
  };

  const completeBtn = document.getElementById('floatCardComplete');
  completeBtn.textContent = thread.status === 'done' ? 'Reopen' : 'Done';
  completeBtn.onclick = () => {
    quickUpdateThreadStatus(thread.id, thread.status === 'done' ? 'todo' : 'done');
  };

  document.getElementById('floatCardOpen').onclick = () => {
    openThreadModal(thread.id);
  };

  card.classList.remove('hidden');
}

async function quickUpdateThreadStatus(id, newStatus) {
  const thread = state.threads.find((t) => t.id === id);
  if (!thread) return;

  const updated = {
    ...thread,
    status: newStatus,
    updatedAt: new Date().toISOString(),
  };

  upsertLocalThread(updated);
  selectThread(id);
  renderAllViews();

  try {
    await apiRequest(`/threads/${id}`, {
      method: 'PUT',
      body: JSON.stringify(updated),
    });
  } catch (err) {
    showToast(err.message, 'error');
  }
}

// ============================================================================
// Threads Tab View
// ============================================================================

function renderThreadsListView() {
  const container = document.getElementById('threadsListGrouped');
  if (!container) return;
  container.innerHTML = '';

  const search = state.searchKeyword.toLowerCase().trim();
  const filterType = state.activeTypeFilter;
  const filterStatus = state.activeStatusFilter;
  const filterSpace = state.activeSpaceFilter;

  let filtered = state.threads.filter((t) => {
    if (filterSpace && t.spaceId !== filterSpace) return false;
    if (filterType !== 'all' && t.type !== filterType) return false;
    if (filterStatus === 'open' && t.status === 'done') return false;
    if (filterStatus === 'done' && t.status !== 'done') return false;
    if (search) {
      const match =
        t.title.toLowerCase().includes(search) ||
        (t.tags && t.tags.some((tag) => tag.toLowerCase().includes(search))) ||
        (t.keywords && t.keywords.some((k) => k.toLowerCase().includes(search)));
      if (!match) return false;
    }
    return true;
  });

  if (filtered.length === 0) {
    container.innerHTML = `
      <div style="text-align:center; padding: 48px; color: var(--text-dim);">
        <p style="font-size: 1.1rem; margin-bottom: 8px;">🕸️ No threads found</p>
        <p style="font-size: 0.85rem;">Create a new thread or adjust your active filters.</p>
      </div>
    `;
    return;
  }

  // Group threads: Overdue, Due Today, This Week, Later, No Date, Done
  const now = new Date();
  const todayEnd = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59);
  const weekEnd = new Date(todayEnd.getTime() + 7 * 86400000);

  const groups = {
    Overdue: [],
    'Due Today': [],
    'This Week': [],
    Later: [],
    'No Date': [],
    Completed: [],
  };

  filtered.forEach((t) => {
    if (t.status === 'done') {
      groups.Completed.push(t);
    } else if (!t.dueAt) {
      groups['No Date'].push(t);
    } else {
      const due = new Date(t.dueAt);
      if (due < now) groups.Overdue.push(t);
      else if (due <= todayEnd) groups['Due Today'].push(t);
      else if (due <= weekEnd) groups['This Week'].push(t);
      else groups.Later.push(t);
    }
  });

  for (const [groupName, items] of Object.entries(groups)) {
    if (items.length === 0) continue;

    const groupEl = document.createElement('div');
    groupEl.className = 'thread-group';

    groupEl.innerHTML = `
      <div class="thread-group-title">
        <span>${groupName}</span>
        <span class="thread-group-count">${items.length}</span>
      </div>
      <div class="thread-cards-stack"></div>
    `;

    const stack = groupEl.querySelector('.thread-cards-stack');
    items.forEach((thread) => {
      const card = createThreadItemCard(thread);
      stack.appendChild(card);
    });

    container.appendChild(groupEl);
  }
}

function createThreadItemCard(thread) {
  const card = document.createElement('div');
  card.className = `thread-item-card ${thread.status === 'done' ? 'done' : ''}`;

  const space = state.spaces.find((s) => s.id === thread.spaceId);
  const isOverdue = thread.dueAt && new Date(thread.dueAt) < new Date() && thread.status !== 'done';

  const tagsHtml = (thread.tags || []).map((tag) => `<span class="thread-tag-chip">#${tag}</span>`).join('');

  card.innerHTML = `
    <div class="thread-item-left">
      <div class="thread-checkbox ${thread.status === 'done' ? 'checked' : ''}">
        ${thread.status === 'done' ? '✓' : ''}
      </div>
      <div class="thread-info">
        <span class="thread-card-title">${thread.title}</span>
        <div class="thread-badges-row">
          <span class="space-badge" style="color:${space?.color || '#32B4FF'}">${space?.name || 'General'}</span>
          <span class="type-badge">${thread.type}</span>
          ${thread.priority === 'high' ? '<span class="priority-badge priority-high">HIGH</span>' : ''}
          ${tagsHtml}
        </div>
      </div>
    </div>
    <div class="thread-item-right">
      ${
        thread.dueAt
          ? `<span class="thread-due-text ${isOverdue ? 'overdue' : ''}">📅 ${new Date(thread.dueAt).toLocaleDateString([], { month: 'short', day: 'numeric' })}</span>`
          : ''
      }
      <button class="thread-del-btn" title="Delete">&times;</button>
    </div>
  `;

  // Toggle status
  const checkbox = card.querySelector('.thread-checkbox');
  checkbox.onclick = (e) => {
    e.stopPropagation();
    quickUpdateThreadStatus(thread.id, thread.status === 'done' ? 'todo' : 'done');
  };

  // Delete with undo
  const delBtn = card.querySelector('.thread-del-btn');
  delBtn.onclick = (e) => {
    e.stopPropagation();
    deleteThreadWithUndo(thread);
  };

  // Open modal
  card.onclick = () => openThreadModal(thread.id);

  return card;
}

async function deleteThreadWithUndo(thread) {
  removeLocalThread(thread.id);
  renderAllViews();

  let undone = false;
  showToast(`Deleted "${thread.title}"`, 'info', {
    label: 'Undo',
    callback: () => {
      undone = true;
      upsertLocalThread(thread);
      renderAllViews();
    },
  });

  setTimeout(async () => {
    if (!undone) {
      try {
        await apiRequest(`/threads/${thread.id}`, { method: 'DELETE' });
      } catch (err) {
        showToast(err.message, 'error');
      }
    }
  }, 4000);
}

// Filter chips in threads tab
document.querySelectorAll('[data-filter-type]').forEach((btn) => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('[data-filter-type]').forEach((b) => b.classList.remove('active'));
    btn.classList.add('active');
    state.activeTypeFilter = btn.dataset.filterType;
    renderThreadsListView();
  });
});

document.querySelectorAll('[data-filter-status]').forEach((btn) => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('[data-filter-status]').forEach((b) => b.classList.remove('active'));
    btn.classList.add('active');
    state.activeStatusFilter = btn.dataset.filterStatus;
    renderThreadsListView();
  });
});

// ============================================================================
// Insights View
// ============================================================================

function renderInsightsView() {
  const openThreads = state.threads.filter((t) => t.status !== 'done');
  const doneThreads = state.threads.filter((t) => t.status === 'done');
  const now = new Date();
  const todayEnd = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59);
  const weekEnd = new Date(todayEnd.getTime() + 7 * 86400000);

  const overdue = openThreads.filter((t) => t.dueAt && new Date(t.dueAt) < now);
  const dueToday = openThreads.filter((t) => t.dueAt && new Date(t.dueAt) >= now && new Date(t.dueAt) <= todayEnd);
  const dueNext7 = openThreads.filter((t) => t.dueAt && new Date(t.dueAt) > todayEnd && new Date(t.dueAt) <= weekEnd);

  document.getElementById('statOpenCount').textContent = openThreads.length;
  document.getElementById('statTotalSub').textContent = `of ${state.threads.length} total threads`;
  document.getElementById('statDueToday').textContent = dueToday.length;
  document.getElementById('statDueNext7').textContent = `${dueNext7.length} in next 7 days`;
  document.getElementById('statOverdue').textContent = overdue.length;
  document.getElementById('statStreak').textContent = `${state.insights?.streak || 0} days`;

  // Next Move Calculation (CONTRACT.md Section 7 formula)
  calculateNextMove(openThreads);

  // Hub & Loose Ends
  calculateHubAndLooseEnds(openThreads);

  // 14-Day Completion Chart
  renderCompletionChart();

  // Activity Feed
  renderActivityFeed();
}

function calculateNextMove(openThreads) {
  if (openThreads.length === 0) {
    document.getElementById('nextMoveTitle').textContent = 'All Caught Up!';
    document.getElementById('nextMoveReason').textContent = 'No open tasks remaining in your spider web.';
    document.getElementById('nextMoveOpenBtn').classList.add('hidden');
    return;
  }

  const now = Date.now();
  let highestScore = -Infinity;
  let topThread = null;
  let topReason = '';

  for (const th of openThreads) {
    // Degree = direct links + shared keywords
    const directLinks = th.links?.length || 0;
    const deg = directLinks;
    let score = deg * 3;

    let reason = '';
    if (th.dueAt) {
      const daysLeft = (new Date(th.dueAt).getTime() - now) / 86400000;
      if (daysLeft < 0) {
        const overdueDays = Math.floor(Math.abs(daysLeft));
        score += 100 + overdueDays;
        reason = `Overdue by ${overdueDays} day(s)`;
      } else if (daysLeft <= 3) {
        score += 40 - 5 * daysLeft;
        reason = `Due in ${Math.ceil(daysLeft)} day(s)`;
      } else {
        score += Math.max(0, 10 - 0.5 * daysLeft);
        reason = `Due on ${new Date(th.dueAt).toLocaleDateString()}`;
      }
    } else {
      reason = 'Strategic open task';
    }

    if (th.priority === 'high') {
      score += 8;
      reason += ' • High Priority';
    }
    if (th.status === 'doing') {
      score += 3;
      reason += ' • Currently in Progress';
    }

    if (score > highestScore) {
      highestScore = score;
      topThread = th;
      topReason = reason;
    }
  }

  if (topThread) {
    document.getElementById('nextMoveTitle').textContent = topThread.title;
    document.getElementById('nextMoveReason').textContent = topReason;
    const btn = document.getElementById('nextMoveOpenBtn');
    btn.classList.remove('hidden');
    btn.onclick = () => openThreadModal(topThread.id);
  }
}

function calculateHubAndLooseEnds(openThreads) {
  let maxDegree = -1;
  let hubThread = null;
  const looseEnds = [];

  for (const th of openThreads) {
    const directLinks = th.links?.length || 0;
    const keywordMatches = state.threads.filter(
      (o) => o.id !== th.id && th.keywords && o.keywords && th.keywords.some((k) => o.keywords.includes(k))
    ).length;

    const degree = directLinks + keywordMatches;
    if (degree >= 2 && degree > maxDegree) {
      maxDegree = degree;
      hubThread = th;
    }

    if (degree === 0) {
      looseEnds.push(th);
    }
  }

  if (hubThread) {
    document.getElementById('hubTitle').textContent = hubThread.title;
    document.getElementById('hubReason').textContent = `Connected to ${maxDegree} other threads via silk strands.`;
    const btn = document.getElementById('hubOpenBtn');
    btn.classList.remove('hidden');
    btn.onclick = () => openThreadModal(hubThread.id);
  } else {
    document.getElementById('hubTitle').textContent = 'No Web Hub';
    document.getElementById('hubReason').textContent = 'Threads are sparse. Add direct links or shared keywords.';
    document.getElementById('hubOpenBtn').classList.add('hidden');
  }

  document.getElementById('looseCount').textContent = `${looseEnds.length} loose threads`;
  document.getElementById('looseReason').textContent =
    looseEnds.length > 0
      ? 'These tasks have zero links or shared keywords with the rest of your web.'
      : 'All threads are woven into the web.';
}

function renderCompletionChart() {
  const container = document.getElementById('completionBarsContainer');
  if (!container) return;
  container.innerHTML = '';

  const completedData = state.insights?.completedByDay || [];
  let maxVal = Math.max(1, ...completedData.map((d) => d.count || 0));

  completedData.forEach((item) => {
    const col = document.createElement('div');
    col.className = 'chart-bar-col';

    const pct = Math.max(4, (item.count / maxVal) * 100);
    const dayLabel = item.date.slice(5); // MM-DD

    col.innerHTML = `
      <span class="chart-bar-val">${item.count > 0 ? item.count : ''}</span>
      <div class="chart-bar-fill" style="height:${pct}%;" title="${item.date}: ${item.count} completed"></div>
      <span class="chart-bar-label">${dayLabel}</span>
    `;
    container.appendChild(col);
  });
}

function renderActivityFeed() {
  const container = document.getElementById('activityTimeline');
  if (!container) return;
  container.innerHTML = '';

  if (state.activity.length === 0) {
    container.innerHTML = `<p class="muted-text">No activity recorded yet.</p>`;
    return;
  }

  state.activity.slice(0, 15).forEach((act) => {
    const item = document.createElement('div');
    item.className = 'activity-item';

    const icons = {
      created: '➕',
      updated: '✏️',
      status: '⚡',
      reminder: '🔔',
      linked: '🔗',
      deleted: '🗑️',
    };

    item.innerHTML = `
      <div class="activity-icon">${icons[act.kind] || '•'}</div>
      <div class="activity-body">
        <div class="activity-msg">${act.message}</div>
        <div class="activity-time">${new Date(act.at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })} • ${new Date(act.at).toLocaleDateString()}</div>
      </div>
    `;
    container.appendChild(item);
  });
}

// ============================================================================
// Settings View
// ============================================================================

function renderSettingsView() {
  updateUserUI();

  // Spaces list
  const list = document.getElementById('spacesManagerList');
  if (!list) return;
  list.innerHTML = '';

  state.spaces.forEach((sp) => {
    const threadCount = state.threads.filter((t) => t.spaceId === sp.id).length;
    const item = document.createElement('div');
    item.className = 'space-manage-item';
    item.innerHTML = `
      <div class="space-manage-info">
        <span class="space-color-badge" style="background:${sp.color}"></span>
        <strong>${sp.name}</strong>
        <span class="muted-text">(${threadCount} threads)</span>
      </div>
      <div class="space-manage-actions">
        <button class="btn btn-sm btn-secondary edit-space-btn">Edit</button>
        <button class="btn btn-sm btn-danger del-space-btn" ${state.spaces.length <= 1 ? 'disabled' : ''}>Delete</button>
      </div>
    `;

    item.querySelector('.edit-space-btn').onclick = () => openSpaceModal(sp);
    item.querySelector('.del-space-btn').onclick = () => deleteSpace(sp);

    list.appendChild(item);
  });
}

// Save profile
document.getElementById('saveProfileBtn').addEventListener('click', async () => {
  const name = document.getElementById('settingName').value.trim();
  const timezone = document.getElementById('settingTimezone').value.trim();

  try {
    const res = await apiRequest('/me', {
      method: 'PATCH',
      body: JSON.stringify({ name, timezone }),
    });
    state.user = res.user;
    updateUserUI();
    showToast('Profile updated successfully!', 'success');
  } catch (err) {
    showToast(err.message, 'error');
  }
});

// Export JSON
document.getElementById('exportJsonBtn').addEventListener('click', () => {
  const data = {
    exportedAt: new Date().toISOString(),
    user: state.user,
    spaces: state.spaces,
    threads: state.threads,
    activity: state.activity,
  };

  const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `spider_mind_export_${new Date().toISOString().slice(0, 10)}.json`;
  a.click();
  URL.revokeObjectURL(url);
  showToast('Database exported successfully', 'success');
});

// Sign Out
document.getElementById('signOutBtn').addEventListener('click', () => {
  setSession(null, null);
  location.reload();
});

// Delete Account
document.getElementById('deleteAccountBtn').addEventListener('click', async () => {
  const pwd = prompt('Please enter your account password to confirm deletion of ALL your data:');
  if (!pwd) return;

  try {
    await apiRequest('/me', {
      method: 'DELETE',
      body: JSON.stringify({ password: pwd }),
    });
    alert('Your account and all associated data have been deleted.');
    setSession(null, null);
    location.reload();
  } catch (err) {
    showToast(err.message, 'error');
  }
});

// ============================================================================
// Thread Editor Modal
// ============================================================================

let currentThreadReminders = [];
let currentThreadChecklist = [];

function openThreadModal(threadId = null) {
  const modal = document.getElementById('threadModal');
  const titleEl = document.getElementById('modalTitle');
  const deleteBtn = document.getElementById('deleteThreadBtn');

  // Populate space select
  const spaceSelect = document.getElementById('threadSpaceInput');
  spaceSelect.innerHTML = state.spaces.map((s) => `<option value="${s.id}">${s.name}</option>`).join('');

  if (threadId) {
    const th = state.threads.find((t) => t.id === threadId);
    if (!th) return;

    titleEl.textContent = 'Edit Thread';
    document.getElementById('threadId').value = th.id;
    document.getElementById('threadTitleInput').value = th.title;
    document.getElementById('threadSpaceInput').value = th.spaceId || state.spaces[0]?.id;
    document.getElementById('threadTypeInput').value = th.type;
    document.getElementById('threadPriorityInput').value = th.priority;
    document.getElementById('threadStatusInput').value = th.status;
    document.getElementById('threadNotesInput').value = th.notes || '';
    document.getElementById('threadTagsInput').value = (th.tags || []).join(', ');

    if (th.dueAt) {
      const d = new Date(th.dueAt);
      const isoLocal = new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
      document.getElementById('threadDueInput').value = isoLocal;
    } else {
      document.getElementById('threadDueInput').value = '';
    }

    currentThreadReminders = [...(th.reminders || [])];
    currentThreadChecklist = [...(th.checklist || [])];

    // Preview server keywords
    const kwCloud = document.getElementById('derivedKeywordsPreview');
    if (th.keywords && th.keywords.length > 0) {
      kwCloud.innerHTML = th.keywords.map((k) => `<span class="keyword-badge">${k}</span>`).join('');
    } else {
      kwCloud.innerHTML = `<span class="muted-text">No keywords derived yet</span>`;
    }

    deleteBtn.classList.remove('hidden');
    deleteBtn.onclick = () => {
      deleteThreadWithUndo(th);
      closeThreadModal();
    };
  } else {
    titleEl.textContent = 'New Thread';
    document.getElementById('threadId').value = '';
    document.getElementById('threadTitleInput').value = '';
    document.getElementById('threadSpaceInput').value = state.spaces[0]?.id || '';
    document.getElementById('threadTypeInput').value = 'task';
    document.getElementById('threadPriorityInput').value = 'medium';
    document.getElementById('threadStatusInput').value = 'todo';
    document.getElementById('threadNotesInput').value = '';
    document.getElementById('threadDueInput').value = '';
    document.getElementById('threadTagsInput').value = '';
    document.getElementById('derivedKeywordsPreview').innerHTML = `<span class="muted-text">Auto-calculated upon save</span>`;

    currentThreadReminders = [];
    currentThreadChecklist = [];
    deleteBtn.classList.add('hidden');
  }

  // Populate link picker
  const linksSelect = document.getElementById('threadLinksSelect');
  const otherThreads = state.threads.filter((t) => t.id !== threadId);
  const activeTh = threadId ? state.threads.find((t) => t.id === threadId) : null;
  linksSelect.innerHTML = otherThreads
    .map(
      (o) =>
        `<option value="${o.id}" ${activeTh?.links?.includes(o.id) ? 'selected' : ''}>${o.title} (${o.type})</option>`
    )
    .join('');

  renderModalReminders();
  renderModalChecklist();

  modal.classList.remove('hidden');
}

function closeThreadModal() {
  document.getElementById('threadModal').classList.add('hidden');
}

document.getElementById('closeThreadModalBtn').addEventListener('click', closeThreadModal);
document.getElementById('cancelThreadModalBtn').addEventListener('click', closeThreadModal);

// Reminders Helpers
function renderModalReminders() {
  const container = document.getElementById('remindersContainer');
  container.innerHTML = '';
  currentThreadReminders.forEach((rem, idx) => {
    const row = document.createElement('div');
    row.className = 'reminder-item-row';
    const localTime = new Date(rem.at).toLocaleString();
    row.innerHTML = `
      <span>🔔 ${localTime}</span>
      <button type="button" class="btn-remove" style="margin-left:auto;">&times;</button>
    `;
    row.querySelector('.btn-remove').onclick = () => {
      currentThreadReminders.splice(idx, 1);
      renderModalReminders();
    };
    container.appendChild(row);
  });
}

document.getElementById('presetDueTimeBtn').addEventListener('click', () => {
  const dueVal = document.getElementById('threadDueInput').value;
  if (!dueVal) return alert('Please set a Due Date & Time first.');
  const at = new Date(dueVal).toISOString();
  addReminder(at);
});

document.getElementById('preset1HourBtn').addEventListener('click', () => {
  const dueVal = document.getElementById('threadDueInput').value;
  if (!dueVal) return alert('Please set a Due Date & Time first.');
  const at = new Date(new Date(dueVal).getTime() - 3600000).toISOString();
  addReminder(at);
});

document.getElementById('preset1DayBtn').addEventListener('click', () => {
  const dueVal = document.getElementById('threadDueInput').value;
  if (!dueVal) return alert('Please set a Due Date & Time first.');
  const at = new Date(new Date(dueVal).getTime() - 86400000).toISOString();
  addReminder(at);
});

function addReminder(isoUtc) {
  const id = Array.from(crypto.getRandomValues(new Uint8Array(12)))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
  currentThreadReminders.push({ id, at: isoUtc, sentAt: null });
  renderModalReminders();
}

// Checklist Helpers
function renderModalChecklist() {
  const container = document.getElementById('checklistContainer');
  container.innerHTML = '';
  currentThreadChecklist.forEach((item, idx) => {
    const row = document.createElement('div');
    row.className = 'checklist-item-row';
    row.innerHTML = `
      <input type="checkbox" ${item.done ? 'checked' : ''}>
      <input type="text" value="${item.text}" placeholder="Checklist item description">
      <button type="button" class="btn-remove">&times;</button>
    `;
    row.querySelector('input[type="checkbox"]').onchange = (e) => {
      item.done = e.target.checked;
    };
    row.querySelector('input[type="text"]').oninput = (e) => {
      item.text = e.target.value;
    };
    row.querySelector('.btn-remove').onclick = () => {
      currentThreadChecklist.splice(idx, 1);
      renderModalChecklist();
    };
    container.appendChild(row);
  });
}

document.getElementById('addChecklistItemBtn').addEventListener('click', () => {
  const id = Array.from(crypto.getRandomValues(new Uint8Array(12)))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
  currentThreadChecklist.push({ id, text: '', done: false });
  renderModalChecklist();
});

// Save Thread Form Submission
document.getElementById('threadForm').addEventListener('submit', async (e) => {
  e.preventDefault();

  let id = document.getElementById('threadId').value;
  if (!id) {
    id = Array.from(crypto.getRandomValues(new Uint8Array(12)))
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('');
  }

  const title = document.getElementById('threadTitleInput').value.trim();
  const spaceId = document.getElementById('threadSpaceInput').value;
  const type = document.getElementById('threadTypeInput').value;
  const priority = document.getElementById('threadPriorityInput').value;
  const status = document.getElementById('threadStatusInput').value;
  const notes = document.getElementById('threadNotesInput').value.trim();

  const dueVal = document.getElementById('threadDueInput').value;
  const dueAt = dueVal ? new Date(dueVal).toISOString() : null;

  const rawTags = document.getElementById('threadTagsInput').value;
  const tags = rawTags
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);

  const selectedLinks = Array.from(document.getElementById('threadLinksSelect').selectedOptions).map((o) => o.value);

  const threadData = {
    id,
    title,
    spaceId,
    type,
    priority,
    status,
    notes,
    dueAt,
    tags,
    links: selectedLinks,
    reminders: currentThreadReminders,
    checklist: currentThreadChecklist.filter((c) => c.text.trim()),
    updatedAt: new Date().toISOString(),
  };

  try {
    const res = await apiRequest(`/threads/${id}`, {
      method: 'PUT',
      body: JSON.stringify(threadData),
    });

    upsertLocalThread(res.thread || threadData);
    closeThreadModal();
    selectThread(id);
    renderAllViews();
    showToast('Thread saved successfully', 'success');
  } catch (err) {
    showToast(err.message, 'error');
  }
});

// ============================================================================
// Spaces Manager Modal
// ============================================================================

function openSpaceModal(space = null) {
  const modal = document.getElementById('spaceModal');
  const title = document.getElementById('spaceModalTitle');

  if (space) {
    title.textContent = 'Edit Space';
    document.getElementById('spaceId').value = space.id;
    document.getElementById('spaceNameInput').value = space.name;
    document.getElementById('spaceColorInput').value = space.color;
  } else {
    title.textContent = 'Add New Space';
    document.getElementById('spaceId').value = '';
    document.getElementById('spaceNameInput').value = '';
    document.getElementById('spaceColorInput').value = '#32B4FF';
  }

  modal.classList.remove('hidden');
}

function closeSpaceModal() {
  document.getElementById('spaceModal').classList.add('hidden');
}

document.getElementById('addSpaceBtn').addEventListener('click', () => openSpaceModal());
document.getElementById('closeSpaceModalBtn').addEventListener('click', closeSpaceModal);
document.getElementById('cancelSpaceModalBtn').addEventListener('click', closeSpaceModal);

document.querySelectorAll('.color-swatch').forEach((swatch) => {
  swatch.addEventListener('click', () => {
    document.getElementById('spaceColorInput').value = swatch.dataset.color;
  });
});

document.getElementById('spaceForm').addEventListener('submit', async (e) => {
  e.preventDefault();

  let id = document.getElementById('spaceId').value;
  if (!id) {
    id = Array.from(crypto.getRandomValues(new Uint8Array(12)))
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('');
  }

  const name = document.getElementById('spaceNameInput').value.trim();
  const color = document.getElementById('spaceColorInput').value;
  const order = state.spaces.length;

  try {
    const res = await apiRequest(`/spaces/${id}`, {
      method: 'PUT',
      body: JSON.stringify({ name, color, order }),
    });

    const idx = state.spaces.findIndex((s) => s.id === id);
    if (idx >= 0) state.spaces[idx] = res.space;
    else state.spaces.push(res.space);

    closeSpaceModal();
    renderSpaceFilters();
    renderSettingsView();
    renderAllViews();
    showToast('Space updated successfully', 'success');
  } catch (err) {
    showToast(err.message, 'error');
  }
});

async function deleteSpace(space) {
  const remaining = state.spaces.filter((s) => s.id !== space.id);
  if (remaining.length === 0) {
    return alert('Cannot delete the last space.');
  }

  const moveTo = prompt(
    `Deleting space "${space.name}". Select target space ID to move existing threads to:\n` +
      remaining.map((s) => `${s.id}: ${s.name}`).join('\n'),
    remaining[0].id
  );

  if (!moveTo) return;

  try {
    await apiRequest(`/spaces/${space.id}?moveTo=${moveTo}`, { method: 'DELETE' });
    state.spaces = state.spaces.filter((s) => s.id !== space.id);
    state.threads.forEach((t) => {
      if (t.spaceId === space.id) t.spaceId = moveTo;
    });

    renderSpaceFilters();
    renderSettingsView();
    renderAllViews();
    showToast(`Space "${space.name}" deleted.`, 'success');
  } catch (err) {
    showToast(err.message, 'error');
  }
}

// ============================================================================
// Auth Modal (Login / Register / Guest)
// ============================================================================

let isRegisterMode = false;

function showAuthModal(show = true) {
  const modal = document.getElementById('authModal');
  modal.classList.toggle('hidden', !show);
}

document.getElementById('tabLogin').addEventListener('click', () => {
  isRegisterMode = false;
  document.getElementById('tabLogin').classList.add('active');
  document.getElementById('tabRegister').classList.remove('active');
  document.getElementById('authNameGroup').classList.add('hidden');
  document.getElementById('authSubmitBtn').textContent = 'Sign In';
  document.getElementById('authError').classList.add('hidden');
});

document.getElementById('tabRegister').addEventListener('click', () => {
  isRegisterMode = true;
  document.getElementById('tabRegister').classList.add('active');
  document.getElementById('tabLogin').classList.remove('active');
  document.getElementById('authNameGroup').classList.remove('hidden');
  document.getElementById('authSubmitBtn').textContent = 'Create Account';
  document.getElementById('authError').classList.add('hidden');
});

document.getElementById('authForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  const email = document.getElementById('authEmailInput').value.trim();
  const password = document.getElementById('authPasswordInput').value;
  const name = document.getElementById('authNameInput').value.trim();

  const endpoint = isRegisterMode ? '/auth/register' : '/auth/login';
  const body = isRegisterMode ? { email, password, name: name || 'Explorer' } : { email, password };

  try {
    const res = await fetch(`${API_BASE}${endpoint}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });

    const data = await res.json();
    if (!res.ok) throw new Error(data.error?.message || 'Authentication failed');

    setSession(data.accessToken, data.refreshToken);
    showAuthModal(false);
    loadInitialData();
  } catch (err) {
    const errBox = document.getElementById('authError');
    errBox.textContent = err.message;
    errBox.classList.remove('hidden');
  }
});

// Quick Guest / Demo Account Generator
document.getElementById('authGuestBtn').addEventListener('click', async () => {
  const rand = Math.random().toString(36).substring(2, 8);
  const email = `guest_${rand}@spidermind.local`;
  const password = 'guestPassword123!';
  const name = `Guest Spider ${rand.toUpperCase()}`;

  try {
    const res = await fetch(`${API_BASE}/auth/register`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, name }),
    });

    const data = await res.json();
    if (!res.ok) throw new Error(data.error?.message || 'Guest account creation failed');

    setSession(data.accessToken, data.refreshToken);
    showAuthModal(false);
    loadInitialData();
    showToast(`Welcome ${name}!`, 'success');
  } catch (err) {
    const errBox = document.getElementById('authError');
    errBox.textContent = err.message;
    errBox.classList.remove('hidden');
  }
});

// ============================================================================
// Initialization
// ============================================================================

window.addEventListener('DOMContentLoaded', () => {
  const canvas = document.getElementById('webCanvas');
  webEngine = new Web3DEngine(canvas);
  webEngine.start();

  setupNavigation();

  if (state.accessToken) {
    loadInitialData();
  } else {
    showAuthModal(true);
  }
});
