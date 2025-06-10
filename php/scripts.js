document.addEventListener('DOMContentLoaded', function() {
    // DOM elements
    const commandTextarea = document.getElementById('command');
    const executeBtn = document.getElementById('executeBtn');
    const logSelect = document.getElementById('logSelect');
    const refreshLogsBtn = document.getElementById('refreshLogsBtn');
    const autoRefreshBtn = document.getElementById('autoRefreshBtn');
    const logOutput = document.getElementById('logOutput');
    const fileExplorer = document.getElementById('fileExplorer');
    const currentPathElement = document.getElementById('currentPath');
    const refreshDirBtn = document.getElementById('refreshDirBtn');
    const quickAccessButtons = document.querySelectorAll('.quick-access-btn');
    
    // Variables
    let currentLogFile = '';
    let autoRefreshInterval = null;
    let isAutoRefreshActive = false;
    let currentDirectory = '/home/pi';
    
    // Function to make AJAX requests
    function makeRequest(action, data, callback) {
        const xhr = new XMLHttpRequest();
        xhr.open('POST', 'index.php', true);
        xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
        
        xhr.onload = function() {
            if (this.status === 200) {
                try {
                    const response = JSON.parse(this.responseText);
                    callback(response);
                } catch (e) {
                    console.error('Error parsing JSON response:', e);
                    console.error('Raw response:', this.responseText);
                    
                    // Try to extract error message from HTML if possible
                    let errorMsg = 'Invalid response from server';
                    if (this.responseText.includes('<b>')) {
                        const matches = this.responseText.match(/<b>([^<]+)<\/b>/);
                        if (matches && matches.length > 1) {
                            errorMsg = matches[1];
                        }
                    }
                    
                    callback({ 
                        status: 'error', 
                        message: 'Server error: ' + errorMsg
                    });
                }
            } else {
                callback({ 
                    status: 'error', 
                    message: 'HTTP error: ' + this.status + ' ' + this.statusText 
                });
            }
        };
        
        xhr.onerror = function() {
            callback({ 
                status: 'error', 
                message: 'Network error - could not connect to server' 
            });
        };
        
        let formData = 'action=' + encodeURIComponent(action);
        for (const key in data) {
            formData += '&' + key + '=' + encodeURIComponent(data[key]);
        }
        
        xhr.send(formData);
    }
    
    // Function to show error messages
    function showError(message) {
        alert('Error: ' + message);
        console.error('Error:', message);
    }
    
    // Function to execute a command
    function executeCommand() {
        const command = commandTextarea.value.trim();
        if (!command) {
            showError('Please enter a command');
            return;
        }
        
        executeBtn.disabled = true;
        executeBtn.textContent = 'Executing...';
        
        makeRequest('execute', { command: command }, function(response) {
            executeBtn.disabled = false;
            executeBtn.textContent = 'Execute';
            
            if (response.status === 'success') {
                refreshLogList(function() {
                    // Select the new log file
                    logSelect.value = response.logFile;
                    loadLogFile(response.logFile);
                });
            } else {
                showError(response.message);
            }
        });
    }
    
    // Function to refresh the log list
    function refreshLogList(callback) {
        makeRequest('getLogs', {}, function(response) {
            if (response.status === 'success') {
                // Clear current options except the first one
                while (logSelect.options.length > 1) {
                    logSelect.remove(1);
                }
                
                // Add new options
                response.logs.forEach(function(log) {
                    const option = document.createElement('option');
                    option.value = log;
                    option.textContent = log;
                    logSelect.appendChild(option);
                });
                
                if (callback) callback();
            } else {
                showError('Error refreshing logs: ' + response.message);
            }
        });
    }
    
    // Function to load a log file
    function loadLogFile(logFile) {
        if (!logFile) {
            logOutput.textContent = 'No log selected';
            currentLogFile = '';
            return;
        }
        
        currentLogFile = logFile;
        
        makeRequest('getLog', { logFile: logFile }, function(response) {
            if (response.status === 'success') {
                logOutput.textContent = response.content || 'Log is empty';
                // Scroll to bottom of log output
                logOutput.scrollTop = logOutput.scrollHeight;
            } else {
                logOutput.textContent = 'Error: ' + response.message;
            }
        });
    }
    
    // Function to toggle auto-refresh
    function toggleAutoRefresh() {
        if (isAutoRefreshActive) {
            // Disable auto-refresh
            clearInterval(autoRefreshInterval);
            autoRefreshBtn.textContent = 'Auto Refresh';
            autoRefreshBtn.classList.remove('active');
            isAutoRefreshActive = false;
        } else {
            // Enable auto-refresh
            if (!currentLogFile) {
                showError('Please select a log file first');
                return;
            }
            
            autoRefreshInterval = setInterval(function() {
                if (currentLogFile) {
                    loadLogFile(currentLogFile);
                }
            }, 2000); // Refresh every 2 seconds
            
            autoRefreshBtn.textContent = 'Stop Auto Refresh';
            autoRefreshBtn.classList.add('active');
            isAutoRefreshActive = true;
        }
    }
    
    // Function to load directory contents
    function loadDirectory(directory) {
        fileExplorer.innerHTML = '<div class="loading">Loading directory...</div>';
        currentPathElement.textContent = directory;
        
        makeRequest('listDirectory', { directory: directory }, function(response) {
            if (response.status === 'success') {
                fileExplorer.innerHTML = '';
                currentDirectory = response.currentDirectory;
                currentPathElement.textContent = currentDirectory;
                
                // Check if we have any items
                if (response.items.length === 0) {
                    fileExplorer.innerHTML = '<div class="loading">No items found in this directory</div>';
                    return;
                }
                
                response.items.forEach(function(item) {
                    const fileItem = document.createElement('div');
                    fileItem.className = 'file-item';
                    
                    // Determine icon based on type
                    let iconClass = 'file-item-icon';
                    if (item.type === 'directory') {
                        iconClass += ' directory';
                    } else if (item.isExecutable) {
                        iconClass += ' executable';
                    }
                    
                    // Create HTML structure
                    let html = `
                        <div class="${iconClass}">
                            ${item.type === 'directory' ? '📁' : (item.isExecutable ? '📜' : '📄')}
                        </div>
                        <div class="file-item-name">${item.name}</div>
                    `;
                    
                    // Add action buttons if needed
                    if (item.isExecutable) {
                        html += `
                            <div class="file-item-actions">
                                <button class="file-action-btn execute" data-path="${item.path}">Execute</button>
                            </div>
                        `;
                    }
                    
                    fileItem.innerHTML = html;
                    
                    // Add event listener for directory navigation
                    if (item.type === 'directory') {
                        fileItem.addEventListener('click', function() {
                            loadDirectory(item.path);
                        });
                    }
                    
                    fileExplorer.appendChild(fileItem);
                });
                
                // Add event listeners for execute buttons
                document.querySelectorAll('.file-action-btn.execute').forEach(function(button) {
                    button.addEventListener('click', function(e) {
                        e.stopPropagation(); // Prevent directory navigation
                        executeScript(this.getAttribute('data-path'));
                    });
                });
            } else {
                fileExplorer.innerHTML = `<div class="loading error">Error: ${response.message}</div>`;
            }
        });
    }
    
    // Function to execute a shell script
    function executeScript(scriptPath) {
        makeRequest('executeScript', { scriptPath: scriptPath }, function(response) {
            if (response.status === 'success') {
                refreshLogList(function() {
                    // Select the new log file
                    logSelect.value = response.logFile;
                    loadLogFile(response.logFile);
                });
            } else {
                showError('Error executing script: ' + response.message);
            }
        });
    }
    
    // Event listeners
    executeBtn.addEventListener('click', executeCommand);
    
    refreshLogsBtn.addEventListener('click', function() {
        refreshLogList();
    });
    
    logSelect.addEventListener('change', function() {
        loadLogFile(this.value);
    });
    
    autoRefreshBtn.addEventListener('click', toggleAutoRefresh);
    
    refreshDirBtn.addEventListener('click', function() {
        loadDirectory(currentDirectory);
    });
    
    // Add event listeners for quick access buttons
    quickAccessButtons.forEach(function(button) {
        button.addEventListener('click', function() {
            loadDirectory(this.getAttribute('data-path'));
        });
    });
    
    // Enable keyboard shortcut for executing commands (Ctrl+Enter)
    commandTextarea.addEventListener('keydown', function(e) {
        if (e.ctrlKey && e.key === 'Enter') {
            executeCommand();
        }
    });
    
    // Initialize the app
    refreshLogList();
    loadDirectory('/home/pi');
});