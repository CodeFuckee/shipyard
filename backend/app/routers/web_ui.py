from fastapi import APIRouter
from fastapi.responses import HTMLResponse

router = APIRouter(tags=["web_ui"])


@router.get("/", response_class=HTMLResponse)
async def admin_page():
    html_content = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Mobile Portainer API Manager</title>
        <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
        <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
        <script src="https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js"></script>
        <style>
            body { padding: 20px; background-color: #f8f9fa; }
            .container-fluid { background: white; padding: 30px; border-radius: 10px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
            .key-item { border-bottom: 1px solid #eee; padding: 10px 0; display: flex; justify-content: space-between; align-items: center; }
            .key-value { font-family: monospace; font-weight: bold; color: #d63384; }
            #login-overlay { position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(255,255,255,0.95); z-index: 1000; display: flex; justify-content: center; align-items: center; }
        </style>
    </head>
    <body>
        <div id="login-overlay">
            <div class="card p-4 shadow">
                <h4 class="mb-3">Admin Login</h4>
                <div class="mb-3">
                    <input type="text" id="admin-user" class="form-control" placeholder="Enter ADMIN_USER">
                </div>
                <div class="mb-3">
                    <input type="password" id="admin-password" class="form-control" placeholder="Enter ADMIN_PASSWORD">
                </div>
                <button onclick="login()" class="btn btn-primary w-100">Login</button>
            </div>
        </div>

        <!-- QR Code Modal -->
        <div class="modal fade" id="qrModal" tabindex="-1" aria-hidden="true">
            <div class="modal-dialog">
                <div class="modal-content">
                    <div class="modal-header">
                        <h5 class="modal-title">API Key QR Code</h5>
                        <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
                    </div>
                    <div class="modal-body text-center">
                        <div id="qrcode" class="d-flex justify-content-center"></div>
                        <p class="mt-3 text-muted small" id="qr-content-preview"></p>
                    </div>
                </div>
            </div>
        </div>

        <div class="container-fluid">
            <h2 class="mb-4">🔑 API Key Manager</h2>

            <div class="card mb-4">
                <div class="card-header">Cluster Nodes</div>
                <div class="card-body">
                    <div class="row g-2 mb-3">
                        <div class="col-md-3">
                            <input type="text" id="node-name" class="form-control" placeholder="Name">
                        </div>
                        <div class="col-md-4">
                            <input type="text" id="node-url" class="form-control" placeholder="Base URL (e.g. http://server:8000)">
                        </div>
                        <div class="col-md-2">
                            <input type="text" id="node-user" class="form-control" placeholder="Admin User">
                        </div>
                        <div class="col-md-2">
                            <input type="password" id="node-pass" class="form-control" placeholder="Admin Pass">
                        </div>
                        <div class="col-md-1">
                            <button onclick="addNode()" class="btn btn-primary w-100">Add</button>
                        </div>
                    </div>
                    <div class="form-check mb-2">
                        <input class="form-check-input" type="checkbox" id="apply-all">
                        <label class="form-check-label" for="apply-all">Apply to all nodes</label>
                    </div>
                    <div id="nodes-list"></div>
                </div>
            </div>

            <div class="card mb-4">
                <div class="card-header">Add New Key</div>
                <div class="card-body">
                    <div class="row g-2">
                        <div class="col-md-5">
                            <input type="text" id="new-key" class="form-control" placeholder="Key (auto-generated if empty)">
                        </div>
                        <div class="col-md-5">
                            <input type="text" id="new-note" class="form-control" placeholder="Description / Note">
                        </div>
                        <div class="col-md-2">
                            <button onclick="addKey()" class="btn btn-success w-100">Add</button>
                        </div>
                    </div>
                </div>
            </div>

            <div class="card">
                <div class="card-header">Existing Keys</div>
                <div class="card-body" id="keys-list">
                    <!-- Keys will be loaded here -->
                </div>
            </div>

            <div class="mt-4 text-muted small">
                <p>API Endpoint: <code>/containers</code></p>
                <p>Header: <code>X-API-Key: &lt;your-key&gt;</code></p>
                <p>API Documentation: <a href="/docs" target="_blank">Swagger UI</a> | <a href="/redoc" target="_blank">ReDoc</a></p>
            </div>
        </div>

        <script>
            const API_URL = "";
            let adminUser = localStorage.getItem('admin_user');
            let adminToken = localStorage.getItem('admin_token');
            let nodes = [];

            if (adminUser && adminToken) {
                document.getElementById('login-overlay').style.display = 'none';
                loadKeys();
                loadNodes();
            }

            async function login() {
                const user = document.getElementById('admin-user').value;
                const password = document.getElementById('admin-password').value;
                // Verify credentials by trying to fetch keys
                const response = await fetch(`${API_URL}/admin/keys`, {
                    headers: {
                        'X-Admin-User': user,
                        'X-Admin-Pass': password
                    }
                });

                if (response.ok) {
                    localStorage.setItem('admin_user', user);
                    localStorage.setItem('admin_token', password);
                    adminUser = user;
                    adminToken = password;
                    document.getElementById('login-overlay').style.display = 'none';
                    loadKeys();
                } else {
                    alert('Invalid Credentials');
                }
            }

            async function loadNodes() {
                const response = await fetch(`${API_URL}/admin/nodes`, {
                    headers: {
                        'X-Admin-User': adminUser,
                        'X-Admin-Pass': adminToken
                    }
                });
                if (!response.ok) return;
                nodes = await response.json();
                const container = document.getElementById('nodes-list');
                if (container) {
                    container.innerHTML = '';
                    nodes.forEach(n => {
                        const div = document.createElement('div');
                        div.className = 'form-check';
                        div.innerHTML = `
                            <input class="form-check-input" type="checkbox" value="${n.id}" id="node-${n.id}">
                            <label class="form-check-label" for="node-${n.id}">
                                ${n.name} <span class="text-muted">(${n.base_url})</span>
                            </label>
                            <button class="btn btn-sm btn-outline-danger ms-2" onclick="deleteNode('${n.id}')">Delete</button>
                        `;
                        container.appendChild(div);
                    });
                }
            }

            async function addNode() {
                const name = document.getElementById('node-name').value;
                const base_url = document.getElementById('node-url').value;
                const user = document.getElementById('node-user').value;
                const pass = document.getElementById('node-pass').value;
                const response = await fetch(`${API_URL}/admin/nodes`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'X-Admin-User': adminUser,
                        'X-Admin-Pass': adminToken
                    },
                    body: JSON.stringify({ name, base_url, admin_user: user, admin_pass: pass })
                });
                if (response.ok) {
                    document.getElementById('node-name').value = '';
                    document.getElementById('node-url').value = '';
                    document.getElementById('node-user').value = '';
                    document.getElementById('node-pass').value = '';
                    loadNodes();
                } else {
                    alert('Failed to add node');
                }
            }

            async function deleteNode(id) {
                const response = await fetch(`${API_URL}/admin/nodes/${id}`, {
                    method: 'DELETE',
                    headers: {
                        'X-Admin-User': adminUser,
                        'X-Admin-Pass': adminToken
                    }
                });
                if (response.ok) loadNodes();
            }

            async function loadKeys() {
                const response = await fetch(`${API_URL}/admin/keys`, {
                    headers: {
                        'X-Admin-User': adminUser,
                        'X-Admin-Pass': adminToken
                    }
                });
                if (response.status === 401) {
                    logout();
                    return;
                }
                const keys = await response.json();
                const list = document.getElementById('keys-list');
                list.innerHTML = '';
                keys.forEach(k => {
                    const div = document.createElement('div');
                    div.className = 'key-item';
                    div.innerHTML = `
                        <div>
                            <span class="key-value">${k.key}</span>
                            <span class="text-muted ms-2">(${k.note || 'No note'})</span>
                            <div class="small text-muted">Created: ${new Date(k.created_at).toLocaleString()}</div>
                        </div>
                        <div>
                            <button onclick="showQR('${k.key}')" class="btn btn-sm btn-info me-2 text-white">QR Code</button>
                            <button onclick="deleteKey('${k.key}')" class="btn btn-sm btn-danger">Delete</button>
                        </div>
                    `;
                    list.appendChild(div);
                });
            }

            async function addKey() {
                const key = document.getElementById('new-key').value;
                const note = document.getElementById('new-note').value;
                const applyAll = document.getElementById('apply-all').checked;
                const selected = Array.from(document.querySelectorAll('#nodes-list input[type=checkbox]:checked')).map(x => x.value);

                const response = await fetch(`${API_URL}/admin/keys`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'X-Admin-User': adminUser,
                        'X-Admin-Pass': adminToken
                    },
                    body: JSON.stringify({ key: key || undefined, note: note, apply_all: applyAll, targets: selected })
                });

                if (response.ok) {
                    document.getElementById('new-key').value = '';
                    document.getElementById('new-note').value = '';
                    document.getElementById('apply-all').checked = false;
                    loadKeys();
                } else {
                    alert('Failed to add key');
                }
            }

            async function deleteKey(key) {
                if (!confirm('Are you sure?')) return;
                const applyAll = document.getElementById('apply-all').checked;
                const selected = Array.from(document.querySelectorAll('#nodes-list input[type=checkbox]:checked')).map(x => x.value);
                const response = await fetch(`${API_URL}/admin/keys/${key}`, {
                    method: 'DELETE',
                    headers: {
                        'X-Admin-User': adminUser,
                        'X-Admin-Pass': adminToken
                    }
                });
                if (response.ok) loadKeys();

                await fetch(`${API_URL}/admin/keys/${key}/propagate`, {
                    method: 'DELETE',
                    headers: {
                        'Content-Type': 'application/json',
                        'X-Admin-User': adminUser,
                        'X-Admin-Pass': adminToken
                    },
                    body: JSON.stringify({ apply_all: applyAll, targets: selected })
                });
            }

            function logout() {
                localStorage.removeItem('admin_user');
                localStorage.removeItem('admin_token');
                location.reload();
            }

            function showQR(apiKey) {
                const modal = new bootstrap.Modal(document.getElementById('qrModal'));
                const qrContainer = document.getElementById('qrcode');
                qrContainer.innerHTML = ''; // Clear previous

                const data = {
                    apikey: apiKey,
                    url: window.location.origin
                };

                const jsonStr = JSON.stringify(data);

                new QRCode(qrContainer, {
                    text: jsonStr,
                    width: 256,
                    height: 256
                });

                // document.getElementById('qr-content-preview').innerText = jsonStr;
                modal.show();
            }
        </script>
    </body>
    </html>
    """
    return html_content
