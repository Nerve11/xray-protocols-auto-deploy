/**
 * Utility functions for dashboard UI
 */

// Toast Notifications
function showToast(message, type = 'info', duration = 3000) {
  const container = document.getElementById('toast-container');
  const toast = document.createElement('div');
  
  const colors = {
    success: 'bg-success-600 border-success-500',
    error: 'bg-danger-600 border-danger-500',
    warning: 'bg-yellow-600 border-yellow-500',
    info: 'bg-primary-600 border-primary-500',
  };

  const icons = {
    success: '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>',
    error: '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>',
    warning: '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"></path>',
    info: '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>',
  };

  toast.className = `${colors[type]} border-l-4 rounded-lg p-4 shadow-lg flex items-center gap-3 animate-slide-in min-w-[300px]`;
  toast.innerHTML = `
    <svg class="w-6 h-6 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      ${icons[type]}
    </svg>
    <span class="flex-1 text-sm font-medium">${message}</span>
    <button class="text-white/80 hover:text-white transition" onclick="this.parentElement.remove()">
      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
      </svg>
    </button>
  `;

  container.appendChild(toast);

  setTimeout(() => {
    toast.style.opacity = '0';
    toast.style.transform = 'translateX(400px)';
    toast.style.transition = 'all 0.3s ease-out';
    setTimeout(() => toast.remove(), 300);
  }, duration);
}

// Copy to Clipboard
function copyToClipboard(text) {
  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(text)
      .then(() => showToast('Copied to clipboard!', 'success'))
      .catch(() => fallbackCopy(text));
  } else {
    fallbackCopy(text);
  }
}

function fallbackCopy(text) {
  const textarea = document.createElement('textarea');
  textarea.value = text;
  textarea.style.position = 'fixed';
  textarea.style.opacity = '0';
  document.body.appendChild(textarea);
  textarea.select();
  try {
    document.execCommand('copy');
    showToast('Copied to clipboard!', 'success');
  } catch (err) {
    showToast('Failed to copy', 'error');
  }
  document.body.removeChild(textarea);
}

// Format Bytes
function formatBytes(bytes, decimals = 2) {
  if (bytes === 0) return '0 Bytes';
  const k = 1024;
  const dm = decimals < 0 ? 0 : decimals;
  const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
}

// Format Uptime
function formatUptime(seconds) {
  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  
  if (days > 0) return `${days}d ${hours}h`;
  if (hours > 0) return `${hours}h ${minutes}m`;
  return `${minutes}m`;
}

// Truncate UUID
function truncateUUID(uuid, length = 8) {
  return uuid.substring(0, length);
}

// Confirm Dialog
function confirmDialog(message) {
  return new Promise((resolve) => {
    const confirmed = confirm(message);
    resolve(confirmed);
  });
}

// Update Connection Status
function updateConnectionStatus(connected) {
  const statusEl = document.getElementById('connection-status');
  if (!statusEl) return;

  const indicator = statusEl.querySelector('div');
  const text = statusEl.querySelector('span');

  if (connected) {
    indicator.className = 'w-2 h-2 rounded-full bg-success-500';
    text.textContent = 'Connected';
  } else {
    indicator.className = 'w-2 h-2 rounded-full bg-danger-500';
    text.textContent = 'Disconnected';
  }
}

// Debounce Function
function debounce(func, wait) {
  let timeout;
  return function executedFunction(...args) {
    const later = () => {
      clearTimeout(timeout);
      func(...args);
    };
    clearTimeout(timeout);
    timeout = setTimeout(later, wait);
  };
}