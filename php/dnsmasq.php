<?php

/**
 * DNSMasq Configuration Manager
 * Simple script to manage DNS blocks in dnsmasq.conf
 */

// Check if it's an AJAX request
$isAjax = !empty($_SERVER['HTTP_X_REQUESTED_WITH']) && strtolower($_SERVER['HTTP_X_REQUESTED_WITH']) == 'xmlhttprequest';

// Handle GET request for edit mode
if ($_SERVER['REQUEST_METHOD'] === 'GET' && isset($_GET['action']) && $_GET['action'] === 'editConfig') {
    $plainTextEditMode = true;
}

// Configuration
$configFile = '/etc/dnsmasq.conf';
$tempFile = '/tmp/dnsmasq.conf.tmp';
$logFile = '/tmp/dnsmasq_manager.log';
$blockIP = "0.0.0.0";

// Variables
$message = $messageType = $commandOutput = '';
$showSetupInstructions = $editingDomainId = $changingTypeId = false;
$plainTextEditMode = isset($plainTextEditMode) ? $plainTextEditMode : false;
$configContent = $ajaxResponse = [];

// Helper functions
function logMessage($msg)
{
    global $logFile;
    @file_put_contents($logFile, date('Y-m-d H:i:s') . " | $msg\n", FILE_APPEND);
}
function execCommand($cmd)
{
    exec($cmd . " 2>&1", $output, $returnCode);
    return ['success' => ($returnCode === 0), 'output' => implode("\n", $output), 'code' => $returnCode];
}
function checkSudoAccess()
{
    return execCommand("sudo -n cat /etc/dnsmasq.conf")['success'];
}
function isValidIP($ip)
{
    return filter_var($ip, FILTER_VALIDATE_IP) !== false;
}

// Get blocked domains
function getBlockedDomains()
{
    global $configFile, $showSetupInstructions, $blockIP;
    $result = execCommand("sudo cat " . escapeshellarg($configFile));
    if (!$result['success']) {
        $showSetupInstructions = true;
        return [];
    }
    $domains = [];
    foreach (explode("\n", $result['output']) as $line) {
        $line = trim($line);
        $disabled = false;
        if (strpos($line, '# address=/') === 0) {
            $disabled = true;
            $line = substr($line, 2); // Remove "# "
        }
        if (strpos($line, 'address=/') === 0) {
            $parts = explode('/', $line);
            if (isset($parts[1]) && isset($parts[2])) {
                $domains[] = [
                    'domain' => $parts[1],
                    'ip' => $parts[2],
                    'type' => ($parts[2] === $blockIP) ? 'block' : 'redirect',
                    'disabled' => $disabled
                ];
            }
        }
    }
    return $domains;
}

// Get config content
function getConfigContent()
{
    global $configFile, $showSetupInstructions;
    $result = execCommand("sudo cat " . escapeshellarg($configFile));
    if (!$result['success']) {
        $showSetupInstructions = true;
        return '';
    }
    return $result['output'];
}

// Generate domain entry HTML
function generateDomainEntryHtml($index, $entry, $editingDomainId, $changingTypeId)
{
    $html = "<tr id=\"domain-row-$index\" class=\"" . ($entry['disabled'] ? 'disabled-entry' : '') . "\">";

    // Status column (checkbox)
    $html .= "<td class=\"status-column\">";
    if ($editingDomainId !== $index && $changingTypeId !== $index) {
        $html .= "<input type=\"checkbox\" class=\"domain-checkbox\" data-index=\"$index\" " . ($entry['disabled'] ? '' : 'checked') . " onchange=\"toggleDomainStatus($index, this.checked)\">";
    }
    $html .= "</td>";

    // Domain column
    $html .= "<td>";
    if ($editingDomainId === $index) {
        $html .= "<form method=\"post\" action=\"\" class=\"edit-domain-form\" id=\"editForm$index\" onsubmit=\"return submitFormAjax(this, 'update');\">
                    <input type=\"hidden\" name=\"old_domain\" value=\"" . htmlspecialchars($entry['domain']) . "\">
                    <input type=\"hidden\" name=\"current_ip\" value=\"" . htmlspecialchars($entry['ip']) . "\">
                    <input type=\"hidden\" name=\"domain_id\" value=\"$index\">
                    <input type=\"text\" name=\"new_domain\" value=\"" . htmlspecialchars($entry['domain']) . "\" required>
                  </form>";
    } else {
        $html .= htmlspecialchars($entry['domain']);
    }
    $html .= "</td>";

    // Type column
    $html .= "<td>";
    if ($changingTypeId === $index) {
        $html .= "<form method=\"post\" action=\"\" id=\"typeForm$index\" onsubmit=\"return submitFormAjax(this, 'changeType');\">
                    <input type=\"hidden\" name=\"domain\" value=\"" . htmlspecialchars($entry['domain']) . "\">
                    <input type=\"hidden\" name=\"current_ip\" value=\"" . htmlspecialchars($entry['ip']) . "\">
                    <input type=\"hidden\" name=\"domain_id\" value=\"$index\">
                    <select name=\"new_type\" onchange=\"toggleChangeTypeIP(this, $index)\">
                        <option value=\"block\"" . ($entry['type'] === 'block' ? ' selected' : '') . ">Block</option>
                        <option value=\"redirect\"" . ($entry['type'] === 'redirect' ? ' selected' : '') . ">Redirect</option>
                    </select>
                    <div class=\"conditional-input\" id=\"new_ip_container_$index\" style=\"display:" . ($entry['type'] === 'redirect' ? 'block' : 'none') . "\">
                        <label for=\"new_ip_$index\">IP Address:</label>
                        <input type=\"text\" id=\"new_ip_$index\" name=\"new_ip\" value=\"" . ($entry['type'] === 'redirect' ? htmlspecialchars($entry['ip']) : '') . "\" placeholder=\"192.168.1.10\">
                    </div>
                  </form>";
    } else {
        $html .= "<form method=\"post\" action=\"\" style=\"display: inline;\" onsubmit=\"return submitFormAjax(this, 'startChangeType');\">
                    <input type=\"hidden\" name=\"domain_id\" value=\"$index\">
                    <button type=\"submit\" class=\"type-badge type-{$entry['type']}\">
                        " . ucfirst(htmlspecialchars($entry['type'])) . "
                    </button>
                  </form>";
        if ($entry['type'] === 'redirect') {
            $html .= "<div class=\"ip-container\">IP: " . htmlspecialchars($entry['ip']) . "</div>";
        }
    }
    $html .= "</td>";

    // Actions column
    $html .= "<td class=\"actions\">";
    if ($editingDomainId === $index) {
        $html .= "<button type=\"submit\" class=\"save\" form=\"editForm$index\">Save</button>
                  <button type=\"button\" class=\"cancel\" onclick=\"submitActionAjax('cancelEdit', $index)\">Cancel</button>";
    } elseif ($changingTypeId === $index) {
        $html .= "<button type=\"submit\" class=\"save\" form=\"typeForm$index\">Save</button>
                  <button type=\"button\" class=\"cancel\" onclick=\"submitActionAjax('cancelChangeType', $index)\">Cancel</button>";
    } else {
        $html .= "<form method=\"post\" action=\"\" style=\"display: inline;\" onsubmit=\"return submitFormAjax(this, 'remove');\">
                    <input type=\"hidden\" name=\"domain\" value=\"" . htmlspecialchars($entry['domain']) . "\">
                    <input type=\"hidden\" name=\"ip\" value=\"" . htmlspecialchars($entry['ip']) . "\">
                    <input type=\"hidden\" name=\"disabled\" value=\"" . ($entry['disabled'] ? '1' : '0') . "\">
                    <button type=\"submit\">Remove</button>
                  </form>
                  <form method=\"post\" action=\"\" style=\"display: inline;\" onsubmit=\"return submitFormAjax(this, 'startEdit');\">
                    <input type=\"hidden\" name=\"domain_id\" value=\"$index\">
                    <button type=\"submit\" class=\"edit\">Edit</button>
                  </form>";
    }
    $html .= "</td>";

    return $html . "</tr>";
}

// Handle form submission
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = $_POST['action'] ?? '';

    switch ($action) {
        case 'add':
            $domain = trim($_POST['domain'] ?? '');
            $type = trim($_POST['type'] ?? 'block');
            $redirectIP = trim($_POST['redirect_ip'] ?? '');

            if (empty($domain)) {
                $message = "Please enter a domain";
                $messageType = 'error';
                break;
            }
            if (!preg_match('/^[a-zA-Z0-9][a-zA-Z0-9-_.]+\.[a-zA-Z]{2,}$/', $domain)) {
                $message = "Invalid domain format";
                $messageType = 'error';
                break;
            }
            if ($type === 'redirect' && (empty($redirectIP) || !isValidIP($redirectIP))) {
                $message = "Please enter a valid IP address for redirect";
                $messageType = 'error';
                break;
            }

            $ip = ($type === 'block') ? $blockIP : $redirectIP;
            $blockedDomains = getBlockedDomains();
            foreach ($blockedDomains as $entry) {
                if ($entry['domain'] === $domain) {
                    $message = "Domain already in list: $domain";
                    $messageType = 'warning';
                    break 2;
                }
            }

            $result = execCommand("echo 'address=/$domain/$ip' | sudo tee -a " . escapeshellarg($configFile));
            if ($result['success']) {
                $message = "Domain added: $domain (" . ($type === 'block' ? 'blocked' : "redirected to $ip") . ")";
                $messageType = 'success';
                logMessage("Added $type for $domain" . ($type === 'redirect' ? " to $ip" : ""));
                execCommand("sudo service dnsmasq restart");
                if ($isAjax) {
                    $blockedDomains = getBlockedDomains();
                    $tableHtml = '';
                    foreach ($blockedDomains as $index => $entry) $tableHtml .= generateDomainEntryHtml($index, $entry, -1, -1);
                    $ajaxResponse = ['success' => true, 'message' => $message, 'messageType' => $messageType, 'html' => $tableHtml];
                }
            } else {
                $message = "Failed to add domain";
                $messageType = 'error';
                $commandOutput = $result['output'];
                $showSetupInstructions = true;
            }
            break;

        case 'remove':
            $domain = trim($_POST['domain'] ?? '');
            $ip = trim($_POST['ip'] ?? '');
            $disabled = $_POST['disabled'] ?? '0';
            if (empty($domain) || empty($ip)) {
                $message = "Missing domain or IP information";
                $messageType = 'error';
                break;
            }

            $timestamp = date('Ymd_His');
            execCommand("sudo cp " . escapeshellarg($configFile) . " /tmp/dnsmasq_backup_$timestamp.conf");
            $prefix = $disabled === '1' ? '# ' : '';
            $result = execCommand("sudo sed -i '/{$prefix}address=\\/$domain\\/$ip/d' " . escapeshellarg($configFile));

            if ($result['success']) {
                $message = "Entry removed: $domain";
                $messageType = 'success';
                logMessage("Removed entry for $domain (IP: $ip)");
                execCommand("sudo service dnsmasq restart");
                if ($isAjax) {
                    $blockedDomains = getBlockedDomains();
                    $tableHtml = '';
                    foreach ($blockedDomains as $index => $entry) $tableHtml .= generateDomainEntryHtml($index, $entry, -1, -1);
                    $ajaxResponse = ['success' => true, 'message' => $message, 'messageType' => $messageType, 'html' => $tableHtml];
                }
            } else {
                $message = "Failed to remove entry";
                $messageType = 'error';
                $commandOutput = $result['output'];
                $showSetupInstructions = true;
            }
            break;

        case 'toggleDomain':
            $domainId = intval($_POST['domain_id'] ?? -1);
            $enable = $_POST['enable'] ?? 'false';
            $blockedDomains = getBlockedDomains();

            if (!isset($blockedDomains[$domainId])) {
                $message = "Domain not found";
                $messageType = 'error';
                break;
            }

            $entry = $blockedDomains[$domainId];
            $timestamp = date('Ymd_His');
            execCommand("sudo cp " . escapeshellarg($configFile) . " /tmp/dnsmasq_backup_$timestamp.conf");

            if ($enable === 'true' && $entry['disabled']) {
                // Enable: remove # prefix
                $result = execCommand("sudo sed -i 's/^# address=\\/" . escapeshellarg($entry['domain']) . "\\/" . escapeshellarg($entry['ip']) . "/address=\\/" . escapeshellarg($entry['domain']) . "\\/" . escapeshellarg($entry['ip']) . "/' " . escapeshellarg($configFile));
                $action_text = "enabled";
            } elseif ($enable === 'false' && !$entry['disabled']) {
                // Disable: add # prefix
                $result = execCommand("sudo sed -i 's/^address=\\/" . escapeshellarg($entry['domain']) . "\\/" . escapeshellarg($entry['ip']) . "/# address=\\/" . escapeshellarg($entry['domain']) . "\\/" . escapeshellarg($entry['ip']) . "/' " . escapeshellarg($configFile));
                $action_text = "disabled";
            } else {
                $message = "No changes needed";
                $messageType = 'info';
                break;
            }

            if ($result['success']) {
                $message = "Domain " . $entry['domain'] . " " . $action_text;
                $messageType = 'success';
                logMessage("Domain " . $entry['domain'] . " " . $action_text);
                execCommand("sudo service dnsmasq restart");
                if ($isAjax) {
                    $blockedDomains = getBlockedDomains();
                    if (isset($blockedDomains[$domainId])) {
                        $entry = $blockedDomains[$domainId];
                        $rowHtml = generateDomainEntryHtml($domainId, $entry, -1, -1);
                        $ajaxResponse = ['success' => true, 'message' => $message, 'messageType' => $messageType, 'rowId' => "domain-row-$domainId", 'html' => $rowHtml];
                    }
                }
            } else {
                $message = "Failed to toggle domain status";
                $messageType = 'error';
                $commandOutput = $result['output'];
            }
            break;

        case 'toggleAll':
            $enable = $_POST['enable'] ?? 'false';
            $blockedDomains = getBlockedDomains();

            if (empty($blockedDomains)) {
                $message = "No domains to toggle";
                $messageType = 'info';
                break;
            }

            $timestamp = date('Ymd_His');
            execCommand("sudo cp " . escapeshellarg($configFile) . " /tmp/dnsmasq_backup_$timestamp.conf");

            $count = 0;
            foreach ($blockedDomains as $entry) {
                if ($enable === 'true' && $entry['disabled']) {
                    // Enable: remove # prefix
                    execCommand("sudo sed -i 's/^# address=\\/" . escapeshellarg($entry['domain']) . "\\/" . escapeshellarg($entry['ip']) . "/address=\\/" . escapeshellarg($entry['domain']) . "\\/" . escapeshellarg($entry['ip']) . "/' " . escapeshellarg($configFile));
                    $count++;
                } elseif ($enable === 'false' && !$entry['disabled']) {
                    // Disable: add # prefix
                    execCommand("sudo sed -i 's/^address=\\/" . escapeshellarg($entry['domain']) . "\\/" . escapeshellarg($entry['ip']) . "/# address=\\/" . escapeshellarg($entry['domain']) . "\\/" . escapeshellarg($entry['ip']) . "/' " . escapeshellarg($configFile));
                    $count++;
                }
            }

            if ($count > 0) {
                $action_text = $enable === 'true' ? 'enabled' : 'disabled';
                $message = "$count domains $action_text";
                $messageType = 'success';
                logMessage("$count domains $action_text");
                execCommand("sudo service dnsmasq restart");
                if ($isAjax) {
                    $blockedDomains = getBlockedDomains();
                    $tableHtml = '';
                    foreach ($blockedDomains as $index => $entry) $tableHtml .= generateDomainEntryHtml($index, $entry, -1, -1);
                    $ajaxResponse = ['success' => true, 'message' => $message, 'messageType' => $messageType, 'html' => $tableHtml];
                }
            } else {
                $message = "No changes needed";
                $messageType = 'info';
            }
            break;

        case 'restart':
            $result = execCommand("sudo service dnsmasq restart");
            $message = $result['success'] ? "DNSMasq service restarted successfully" : "Failed to restart DNSMasq service";
            $messageType = $result['success'] ? 'success' : 'error';
            if ($result['success']) logMessage("Restarted DNSMasq service");
            else {
                $commandOutput = $result['output'];
                $showSetupInstructions = true;
            }
            break;

        case 'startEdit':
            $editingDomainId = intval($_POST['domain_id'] ?? -1);
            if ($isAjax) {
                $blockedDomains = getBlockedDomains();
                if (isset($blockedDomains[$editingDomainId])) {
                    $entry = $blockedDomains[$editingDomainId];
                    $ajaxResponse = ['success' => true, 'rowId' => "domain-row-$editingDomainId", 'html' => generateDomainEntryHtml($editingDomainId, $entry, $editingDomainId, -1)];
                } else {
                    $ajaxResponse = ['success' => false, 'message' => 'Domain not found', 'messageType' => 'error'];
                }
            }
            break;

        case 'startChangeType':
            $changingTypeId = intval($_POST['domain_id'] ?? -1);
            if ($isAjax) {
                $blockedDomains = getBlockedDomains();
                if (isset($blockedDomains[$changingTypeId])) {
                    $entry = $blockedDomains[$changingTypeId];
                    $ajaxResponse = ['success' => true, 'rowId' => "domain-row-$changingTypeId", 'html' => generateDomainEntryHtml($changingTypeId, $entry, -1, $changingTypeId)];
                } else {
                    $ajaxResponse = ['success' => false, 'message' => 'Domain not found', 'messageType' => 'error'];
                }
            }
            break;

        case 'changeType':
            $domainId = intval($_POST['domain_id'] ?? -1);
            $domain = trim($_POST['domain'] ?? '');
            $currentIP = trim($_POST['current_ip'] ?? '');
            $newType = trim($_POST['new_type'] ?? 'block');
            $newIP = trim($_POST['new_ip'] ?? '');

            if (empty($domain)) {
                $message = "Missing domain information";
                $messageType = 'error';
                $changingTypeId = $domainId;
                break;
            }
            if ($newType === 'redirect' && (empty($newIP) || !isValidIP($newIP))) {
                $message = "Please enter a valid IP address for redirect";
                $messageType = 'error';
                $changingTypeId = $domainId;
                break;
            }

            $newIP = ($newType === 'block') ? $blockIP : $newIP;
            if ($currentIP === $newIP) {
                $message = "No changes made";
                $messageType = 'info';
                break;
            }

            $timestamp = date('Ymd_His');
            execCommand("sudo cp " . escapeshellarg($configFile) . " /tmp/dnsmasq_backup_$timestamp.conf");
            $result1 = execCommand("sudo sed -i '/address=\\/" . escapeshellarg($domain) . "\\/" . escapeshellarg($currentIP) . "/d' " . escapeshellarg($configFile));
            $result2 = execCommand("sudo sed -i '/# address=\\/" . escapeshellarg($domain) . "\\/" . escapeshellarg($currentIP) . "/d' " . escapeshellarg($configFile));
            $result3 = execCommand("echo 'address=/$domain/$newIP' | sudo tee -a " . escapeshellarg($configFile));

            if (($result1['success'] || $result2['success']) && $result3['success']) {
                $message = "Changed type for $domain to " . ($newType === 'block' ? 'block' : "redirect to $newIP");
                $messageType = 'success';
                logMessage("Changed type for $domain to " . ($newType === 'block' ? 'block' : "redirect to $newIP"));
                execCommand("sudo service dnsmasq restart");
                if ($isAjax) {
                    $blockedDomains = getBlockedDomains();
                    $tableHtml = '';
                    foreach ($blockedDomains as $index => $entry) $tableHtml .= generateDomainEntryHtml($index, $entry, -1, -1);
                    $ajaxResponse = ['success' => true, 'message' => $message, 'messageType' => $messageType, 'html' => $tableHtml];
                }
            } else {
                $message = "Failed to change type";
                $messageType = 'error';
                $commandOutput = $result3['output'];
                $showSetupInstructions = true;
                $changingTypeId = $domainId;
            }
            break;

        case 'cancelChangeType':
            $domainId = intval($_POST['domain_id'] ?? -1);
            if ($isAjax) {
                $blockedDomains = getBlockedDomains();
                if (isset($blockedDomains[$domainId])) {
                    $entry = $blockedDomains[$domainId];
                    $ajaxResponse = ['success' => true, 'rowId' => "domain-row-$domainId", 'html' => generateDomainEntryHtml($domainId, $entry, -1, -1)];
                } else {
                    $ajaxResponse = ['success' => false, 'message' => 'Domain not found', 'messageType' => 'error'];
                }
            }
            break;

        case 'update':
            $oldDomain = trim($_POST['old_domain'] ?? '');
            $newDomain = trim($_POST['new_domain'] ?? '');
            $currentIP = trim($_POST['current_ip'] ?? '');
            $domainId = intval($_POST['domain_id'] ?? -1);

            if (empty($oldDomain) || empty($newDomain) || empty($currentIP)) {
                $message = "Missing domain or IP information";
                $messageType = 'error';
                $editingDomainId = $domainId;
                break;
            }
            if (!preg_match('/^[a-zA-Z0-9][a-zA-Z0-9-_.]+\.[a-zA-Z]{2,}$/', $newDomain)) {
                $message = "Invalid domain format";
                $messageType = 'error';
                $editingDomainId = $domainId;
                break;
            }
            if ($oldDomain === $newDomain) {
                $message = "No changes made";
                $messageType = 'info';
                break;
            }

            $blockedDomains = getBlockedDomains();
            foreach ($blockedDomains as $entry) {
                if ($entry['domain'] === $newDomain && $oldDomain !== $newDomain) {
                    $message = "New domain already exists: $newDomain";
                    $messageType = 'error';
                    $editingDomainId = $domainId;
                    break 2;
                }
            }

            $timestamp = date('Ymd_His');
            execCommand("sudo cp " . escapeshellarg($configFile) . " /tmp/dnsmasq_backup_$timestamp.conf");
            $result1 = execCommand("sudo sed -i '/address=\\/" . escapeshellarg($oldDomain) . "\\/" . escapeshellarg($currentIP) . "/d' " . escapeshellarg($configFile));
            $result2 = execCommand("sudo sed -i '/# address=\\/" . escapeshellarg($oldDomain) . "\\/" . escapeshellarg($currentIP) . "/d' " . escapeshellarg($configFile));
            $result3 = execCommand("echo 'address=/$newDomain/$currentIP' | sudo tee -a " . escapeshellarg($configFile));

            if (($result1['success'] || $result2['success']) && $result3['success']) {
                $message = "Domain updated from '$oldDomain' to '$newDomain'";
                $messageType = 'success';
                logMessage("Updated domain from $oldDomain to $newDomain (IP: $currentIP)");
                execCommand("sudo service dnsmasq restart");
                if ($isAjax) {
                    $blockedDomains = getBlockedDomains();
                    $tableHtml = '';
                    foreach ($blockedDomains as $index => $entry) $tableHtml .= generateDomainEntryHtml($index, $entry, -1, -1);
                    $ajaxResponse = ['success' => true, 'message' => $message, 'messageType' => $messageType, 'html' => $tableHtml];
                }
            } else {
                $message = "Failed to update domain";
                $messageType = 'error';
                $commandOutput = $result3['output'];
                $showSetupInstructions = true;
                $editingDomainId = $domainId;
            }
            break;

        case 'cancelEdit':
            $domainId = intval($_POST['domain_id'] ?? -1);
            if ($isAjax) {
                $blockedDomains = getBlockedDomains();
                if (isset($blockedDomains[$domainId])) {
                    $entry = $blockedDomains[$domainId];
                    $ajaxResponse = ['success' => true, 'rowId' => "domain-row-$domainId", 'html' => generateDomainEntryHtml($domainId, $entry, -1, -1)];
                } else {
                    $ajaxResponse = ['success' => false, 'message' => 'Domain not found', 'messageType' => 'error'];
                }
            }
            break;

        case 'saveConfig':
            $newContent = $_POST['config_content'] ?? '';
            if (empty($newContent)) {
                $message = "Configuration content cannot be empty";
                $messageType = 'error';
                $plainTextEditMode = true;
                $configContent = getConfigContent();
                break;
            }

            $timestamp = date('Ymd_His');
            execCommand("sudo cp " . escapeshellarg($configFile) . " /tmp/dnsmasq_backup_$timestamp.conf");

            if (@file_put_contents($tempFile, $newContent)) {
                $result = execCommand("sudo cp " . escapeshellarg($tempFile) . " " . escapeshellarg($configFile));
                if ($result['success']) {
                    $message = "Configuration saved successfully";
                    $messageType = 'success';
                    logMessage("Updated dnsmasq.conf via text editor");
                    execCommand("sudo service dnsmasq restart");
                    @unlink($tempFile);
                    $plainTextEditMode = false;
                    if ($isAjax) $ajaxResponse = ['success' => true, 'message' => $message, 'messageType' => $messageType, 'reload' => true];
                } else {
                    $message = "Failed to save configuration";
                    $messageType = 'error';
                    $commandOutput = $result['output'];
                    $showSetupInstructions = true;
                    $plainTextEditMode = true;
                    $configContent = $newContent;
                }
            } else {
                $message = "Failed to write to temporary file";
                $messageType = 'error';
                $plainTextEditMode = true;
                $configContent = $newContent;
            }
            break;

        case 'checkConfig':
            $result = execCommand("sudo dnsmasq --test");
            $message = $result['success'] ? "DNSMasq configuration is valid" : "DNSMasq configuration test failed";
            $messageType = $result['success'] ? 'success' : 'error';
            if (!$result['success']) $commandOutput = $result['output'];
            break;

        case 'refreshTable':
            if ($isAjax) {
                $blockedDomains = getBlockedDomains();
                $tableHtml = '';
                foreach ($blockedDomains as $index => $entry) $tableHtml .= generateDomainEntryHtml($index, $entry, -1, -1);
                $ajaxResponse = ['success' => true, 'html' => $tableHtml];
            }
            break;
    }

    if ($isAjax && !empty($ajaxResponse)) {
        header('Content-Type: application/json');
        echo json_encode($ajaxResponse);
        exit;
    }
    if ($isAjax) $ajaxResponse = ['success' => false, 'message' => $message, 'messageType' => $messageType];
    if ($isAjax) {
        header('Content-Type: application/json');
        echo json_encode($ajaxResponse);
        exit;
    }
}

// Initialize
if (!$showSetupInstructions) $showSetupInstructions = !checkSudoAccess();
$blockedDomains = getBlockedDomains();
if ($plainTextEditMode && empty($configContent)) $configContent = getConfigContent();

include 'header.php';

?>
<!DOCTYPE html>
<html lang="en">

<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DNSMasq Block Manager</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 0;
            padding: 20px;
            background-color: #f5f5f5;
        }

        .container {
            max-width: 800px;
            margin: 0 auto;
            background-color: white;
            padding: 20px;
            border-radius: 5px;
            box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1);
        }

        h1 {
            color: #333;
        }

        .form-group {
            margin-bottom: 15px;
        }

        label {
            display: block;
            margin-bottom: 5px;
            font-weight: bold;
        }

        input[type="text"],
        textarea,
        select {
            width: 100%;
            padding: 8px;
            border: 1px solid #ddd;
            border-radius: 4px;
            box-sizing: border-box;
        }

        textarea {
            min-height: 300px;
            font-family: monospace;
            font-size: 14px;
        }

        select {
            background-color: white;
        }

        .buttons {
            margin-top: 10px;
        }

        button {
            padding: 8px 16px;
            margin-right: 10px;
            border: none;
            border-radius: 4px;
            cursor: pointer;
            transition: all 0.2s ease;
            font-family: Arial, sans-serif;
            font-size: 14px;
        }

        button[type="submit"],
        button.save {
            background-color: #4CAF50;
            color: white;
        }

        button[type="submit"]:hover,
        button.save:hover {
            background-color: #45a049;
        }

        button.edit {
            background-color: #2196F3;
            color: white;
        }

        button.edit:hover {
            background-color: #0b7dda;
        }

        button.cancel {
            background-color: #f44336;
            color: white;
        }

        button.cancel:hover {
            background-color: #d32f2f;
        }

        button.check {
            background-color: #FF9800;
            color: white;
        }

        button.check:hover {
            background-color: #F57C00;
        }

        button.refresh {
            background-color: #607D8B;
            color: white;
        }

        button.refresh:hover {
            background-color: #455A64;
        }

        .toast-container {
            position: fixed;
            top: 20px;
            right: 20px;
            z-index: 9999;
            max-width: 300px;
        }

        .toast {
            padding: 12px 16px;
            margin-bottom: 10px;
            border-radius: 4px;
            box-shadow: 0 4px 8px rgba(0, 0, 0, 0.1);
            display: flex;
            align-items: center;
            animation: toast-in 0.3s ease, toast-out 0.3s ease 4.7s forwards;
            position: relative;
            overflow: hidden;
        }

        .toast.success {
            background-color: #d4edda;
            color: #155724;
            border-left: 4px solid #28a745;
        }

        .toast.error {
            background-color: #f8d7da;
            color: #721c24;
            border-left: 4px solid #dc3545;
        }

        .toast.warning {
            background-color: #fff3cd;
            color: #856404;
            border-left: 4px solid #ffc107;
        }

        .toast.info {
            background-color: #e2f0ff;
            color: #0c5460;
            border-left: 4px solid #17a2b8;
        }

        .toast-progress {
            position: absolute;
            bottom: 0;
            left: 0;
            height: 3px;
            background-color: rgba(0, 0, 0, 0.1);
            width: 100%;
            animation: toast-progress 5s linear;
        }

        .toast-close {
            position: absolute;
            top: 5px;
            right: 5px;
            cursor: pointer;
            font-size: 16px;
            opacity: 0.5;
        }

        .toast-close:hover {
            opacity: 1;
        }

        @keyframes toast-in {
            from {
                transform: translateX(100%);
                opacity: 0;
            }

            to {
                transform: translateX(0);
                opacity: 1;
            }
        }

        @keyframes toast-out {
            from {
                transform: translateX(0);
                opacity: 1;
            }

            to {
                transform: translateX(100%);
                opacity: 0;
            }
        }

        @keyframes toast-progress {
            from {
                width: 100%;
            }

            to {
                width: 0%;
            }
        }

        .command-output {
            background-color: #f8f9fa;
            border: 1px solid #ddd;
            padding: 10px;
            margin-top: 10px;
            font-family: monospace;
            white-space: pre-wrap;
            max-height: 200px;
            overflow-y: auto;
            display: none;
        }

        .command-output.visible {
            display: block;
        }

        .setup-instructions {
            background-color: #e2f0ff;
            padding: 15px;
            border-radius: 4px;
            margin: 20px 0;
        }

        .actions {
            display: flex;
            flex-wrap: wrap;
            gap: 5px;
        }

        .edit-form {
            background-color: #f9f9f9;
            padding: 15px;
            border-radius: 4px;
            margin: 20px 0;
            border: 1px solid #ddd;
        }

        .status-indicator {
            display: inline-block;
            width: 10px;
            height: 10px;
            border-radius: 50%;
            margin-right: 5px;
        }

        .status-active {
            background-color: #4CAF50;
        }

        .status-error {
            background-color: #f44336;
        }

        .tools-section {
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
            margin-bottom: 20px;
        }

        .type-badge {
            padding: 8px 16px;
            border: none;
            border-radius: 4px;
            cursor: pointer;
            transition: all 0.2s ease;
            color: white;
            font-family: Arial, sans-serif;
            font-size: 14px;
            font-weight: normal;
            margin-right: 10px;
        }

        .type-block {
            background: linear-gradient(135deg, #e4ab0a, #ba4a00);
        }

        .type-block:hover {
            background: linear-gradient(135deg, #ba4a00, #a04000);
            transform: translateY(-1px);
            box-shadow: 0 4px 8px rgba(0, 0, 0, 0.3);
        }

        .type-redirect {
            background: linear-gradient(135deg, #3498db, #2980b9);
        }

        .type-redirect:hover {
            background: linear-gradient(135deg, #2980b9, #1f618d);
            transform: translateY(-1px);
            box-shadow: 0 4px 8px rgba(0, 0, 0, 0.3);
        }

        .ip-container {
            color: #666;
            font-size: 11px;
            margin-top: 5px;
            font-style: italic;
        }

        .conditional-input {
            margin-top: 10px;
            padding-top: 10px;
            border-top: 1px solid #eee;
        }

        .table-responsive {
            overflow-x: auto;
        }

        .loading {
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background-color: rgba(255, 255, 255, 0.9);
            display: flex;
            justify-content: center;
            align-items: center;
            z-index: 10000;
            display: none;
            backdrop-filter: blur(1px);
            transition: opacity 0.2s ease;
        }

        .loading-indicator {
            width: 40px;
            height: 40px;
            position: relative;
        }

        .loading-circular {
            animation: rotate 2s linear infinite;
            height: 100%;
            transform-origin: center center;
            width: 100%;
            position: absolute;
            top: 0;
            bottom: 0;
            left: 0;
            right: 0;
            margin: auto;
        }

        .loading-path {
            stroke-dasharray: 150, 200;
            stroke-dashoffset: -10;
            animation: dash 1.5s ease-in-out infinite;
            stroke-linecap: round;
            stroke: #4285f4;
        }

        @keyframes rotate {
            100% {
                transform: rotate(360deg);
            }
        }

        @keyframes dash {
            0% {
                stroke-dasharray: 1, 200;
                stroke-dashoffset: 0;
            }

            50% {
                stroke-dasharray: 89, 200;
                stroke-dashoffset: -35;
            }

            100% {
                stroke-dasharray: 89, 200;
                stroke-dashoffset: -124;
            }
        }

        .page-info {
            text-align: right;
            font-size: 12px;
            color: #666;
            margin-top: 20px;
        }

        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 20px;
        }

        table,
        th,
        td {
            border: 1px solid #ddd;
        }

        th,
        td {
            padding: 10px;
            text-align: left;
        }

        th {
            background-color: #f2f2f2;
        }

        tr {
            transition: background-color 0.2s ease;
        }

        tr:nth-child(even) {
            background-color: #f9f9f9;
        }

        tr:hover {
            background-color: #f0f8ff;
        }

        .user-info {
            padding-top: 0px;
            padding-bottom: 0px;
            font-size: 0.9em;
            color: #666;
        }

        #domains-table tbody {
            transition: opacity 0.1s ease;
        }

        .table-updating {
            opacity: 0.7;
        }

        .disabled-entry {
            opacity: 0.6;
            background-color: #f8f9fa !important;
        }

        .disabled-entry:hover {
            background-color: #e9ecef !important;
        }

        .domain-checkbox {
            cursor: pointer;
        }

        .status-column {
            width: 50px;
            text-align: center;
        }

        .bulk-actions {
            margin-bottom: 15px;
            padding: 10px;
            background-color: #f8f9fa;
            border-radius: 4px;
            border: 1px solid #dee2e6;
        }

        .bulk-actions label {
            display: inline;
            margin-left: 5px;
            margin-right: 15px;
            font-weight: normal;
        }

        #master-checkbox {
            margin-right: 5px;
        }
    </style>
    <script>
        document.addEventListener('DOMContentLoaded', function() {
            const t = document.getElementById('type');
            t && toggleRedirectIP(t);
            const i = "<?= addslashes($message) ?>";
            const m = "<?= $messageType ?>";
            i && showToast(i, m);
            updateMasterCheckbox();
        });

        function toggleRedirectIP(s) {
            const c = document.getElementById('redirect_ip_container');
            c.style.display = s.value === 'redirect' ? 'block' : 'none';
        }

        function toggleChangeTypeIP(s, f) {
            const c = document.getElementById('new_ip_container_' + f);
            c.style.display = s.value === 'redirect' ? 'block' : 'none';
        }

        function showLoading() {
            const l = document.getElementById('loading');
            l.style.display = 'flex';
            l.style.opacity = '0';
            setTimeout(() => l.style.opacity = '1', 10);
        }

        function hideLoading() {
            const l = document.getElementById('loading');
            l.style.opacity = '0';
            setTimeout(() => l.style.display = 'none', 200);
        }

        function showToast(m, t) {
            let c = document.getElementById('toast-container');
            if (!c) {
                c = document.createElement('div');
                c.id = 'toast-container';
                c.className = 'toast-container';
                document.body.appendChild(c);
            }
            const toast = document.createElement('div');
            toast.className = 'toast ' + (t || 'info');
            toast.innerHTML = `<div class="toast-message">${m}</div><span class="toast-close" onclick="this.parentElement.remove()">&times;</span><div class="toast-progress"></div>`;
            c.appendChild(toast);
            setTimeout(() => {
                if (toast.parentElement) toast.remove();
            }, 5000);
        }

        function showCommandOutput(o) {
            const d = document.getElementById('command-output');
            d.textContent = o;
            d.className = 'command-output visible';
        }

        function updateRowSmoothly(rowId, newHtml) {
            const row = document.getElementById(rowId);
            if (row) {
                row.style.transition = 'opacity 0.2s ease';
                row.style.opacity = '0';
                setTimeout(() => {
                    row.outerHTML = newHtml;
                    const newRow = document.getElementById(rowId);
                    if (newRow) {
                        newRow.style.opacity = '0';
                        setTimeout(() => newRow.style.opacity = '1', 10);
                    }
                    updateMasterCheckbox();
                }, 200);
            }
        }

        function updateTableSmoothly(newHtml) {
            const tbody = document.querySelector('#domains-table tbody');
            if (tbody) {
                tbody.classList.add('table-updating');
                setTimeout(() => {
                    tbody.innerHTML = newHtml;
                    tbody.classList.remove('table-updating');
                    updateMasterCheckbox();
                }, 100);
            }
        }

        function toggleDomainStatus(index, enabled) {
            showLoading();
            const fd = new FormData();
            fd.append('action', 'toggleDomain');
            fd.append('domain_id', index);
            fd.append('enable', enabled ? 'true' : 'false');
            const x = new XMLHttpRequest();
            x.open('POST', window.location.href, true);
            x.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
            x.onload = function() {
                hideLoading();
                if (x.status === 200) {
                    try {
                        const r = JSON.parse(x.responseText);
                        if (r.message) showToast(r.message, r.messageType || 'info');
                        if (r.success && r.rowId && r.html) {
                            updateRowSmoothly(r.rowId, r.html);
                        }
                    } catch (e) {
                        console.error('Error parsing JSON:', e);
                        showToast('Error processing server response', 'error');
                    }
                } else {
                    showToast('Server error: ' + x.status, 'error');
                }
            };
            x.onerror = function() {
                hideLoading();
                showToast('Request failed', 'error');
            };
            x.send(fd);
        }

        function toggleAll(enable) {
            showLoading();
            const fd = new FormData();
            fd.append('action', 'toggleAll');
            fd.append('enable', enable ? 'true' : 'false');
            const x = new XMLHttpRequest();
            x.open('POST', window.location.href, true);
            x.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
            x.onload = function() {
                hideLoading();
                if (x.status === 200) {
                    try {
                        const r = JSON.parse(x.responseText);
                        if (r.message) showToast(r.message, r.messageType || 'info');
                        if (r.success && r.html) {
                            updateTableSmoothly(r.html);
                        }
                    } catch (e) {
                        console.error('Error parsing JSON:', e);
                        showToast('Error processing server response', 'error');
                    }
                } else {
                    showToast('Server error: ' + x.status, 'error');
                }
            };
            x.onerror = function() {
                hideLoading();
                showToast('Request failed', 'error');
            };
            x.send(fd);
        }

        function updateMasterCheckbox() {
            const checkboxes = document.querySelectorAll('.domain-checkbox');
            const master = document.getElementById('master-checkbox');
            if (!checkboxes.length || !master) return;
            const checkedCount = Array.from(checkboxes).filter(cb => cb.checked).length;
            master.checked = checkedCount === checkboxes.length;
            master.indeterminate = checkedCount > 0 && checkedCount < checkboxes.length;
        }

        function submitFormAjax(f, a) {
            showLoading();
            const fd = new FormData(f);
            fd.append('action', a);
            const x = new XMLHttpRequest();
            x.open('POST', window.location.href, true);
            x.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
            x.onload = function() {
                hideLoading();
                if (x.status === 200) {
                    try {
                        const r = JSON.parse(x.responseText);
                        if (r.reload) {
                            window.location.href = window.location.href.split('?')[0];
                            return;
                        }
                        if (r.message) showToast(r.message, r.messageType || 'info');
                        if (r.commandOutput) showCommandOutput(r.commandOutput);
                        if (r.success && r.rowId && r.html) {
                            updateRowSmoothly(r.rowId, r.html);
                        } else if (r.success && r.html && !r.rowId) {
                            updateTableSmoothly(r.html);
                        }
                        if (a === 'add' && r.success && f.id === 'addDomainForm') {
                            f.reset();
                            const ts = document.getElementById('type');
                            if (ts) toggleRedirectIP(ts);
                        }
                    } catch (e) {
                        console.error('Error parsing JSON:', e);
                        showToast('Error processing server response', 'error');
                    }
                } else {
                    showToast('Server error: ' + x.status, 'error');
                }
            };
            x.onerror = function() {
                hideLoading();
                showToast('Request failed', 'error');
            };
            x.send(fd);
            return false;
        }

        function submitActionAjax(a, d) {
            showLoading();
            const fd = new FormData();
            fd.append('action', a);
            if (d !== undefined) fd.append('domain_id', d);
            const x = new XMLHttpRequest();
            x.open('POST', window.location.href, true);
            x.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
            x.onload = function() {
                hideLoading();
                if (x.status === 200) {
                    try {
                        const r = JSON.parse(x.responseText);
                        if (r.reload) {
                            window.location.href = window.location.href.split('?')[0];
                            return;
                        }
                        if (r.message) showToast(r.message, r.messageType || 'info');
                        if (r.commandOutput) showCommandOutput(r.commandOutput);
                        if (r.success && r.rowId && r.html) {
                            updateRowSmoothly(r.rowId, r.html);
                        } else if (r.success && r.html && !r.rowId) {
                            updateTableSmoothly(r.html);
                        }
                    } catch (e) {
                        console.error('Error parsing JSON:', e);
                        showToast('Error processing server response', 'error');
                    }
                } else {
                    showToast('Server error: ' + x.status, 'error');
                }
            };
            x.onerror = function() {
                hideLoading();
                showToast('Request failed', 'error');
            };
            x.send(fd);
        }

        function refreshTable() {
            submitActionAjax('refreshTable');
        }
    </script>
</head>

<!-- <body> -->
<div id="loading" class="loading">
    <div class="loading-indicator"><svg class="loading-circular" viewBox="25 25 50 50">
            <circle class="loading-path" cx="50" cy="50" r="20" fill="none" stroke-width="3" stroke-miterlimit="10" />
        </svg></div>
</div>
<div id="toast-container" class="toast-container"></div>
<div class="container">
    <h1 style="margin-top: 0px; margin-bottom: 0px;">DNSMasq Block Manager</h1>
    <div class="user-info">
        <?php $s = execCommand("sudo service dnsmasq status | grep Active");
        $a = strpos($s['output'], 'active (running)') !== false; ?>
        <p><span class="status-indicator <?= $a ? 'status-active' : 'status-error' ?>"></span>DNSMasq Service: <?= $a ? 'Running' : 'Stopped' ?></p>
    </div>

    <?php if ($showSetupInstructions): ?>
        <div class="setup-instructions">
            <h3>Setup Instructions</h3>
            <p>For this script to work, you need to configure sudo access for the web server user:</p>
            <ol>
                <li>Run this command: <code>sudo vi /etc/sudoers.d/www-dnsmasq</code></li>
                <li>Add the following lines:</li>
                <pre>www-data ALL=(ALL) NOPASSWD: /bin/cat /etc/dnsmasq.conf
www-data ALL=(ALL) NOPASSWD: /bin/cp /etc/dnsmasq.conf /tmp/dnsmasq_backup_*.conf
www-data ALL=(ALL) NOPASSWD: /bin/cp /tmp/dnsmasq.conf.tmp /etc/dnsmasq.conf
www-data ALL=(ALL) NOPASSWD: /usr/bin/tee -a /etc/dnsmasq.conf
www-data ALL=(ALL) NOPASSWD: /bin/sed -i * /etc/dnsmasq.conf
www-data ALL=(ALL) NOPASSWD: /usr/sbin/service dnsmasq restart
www-data ALL=(ALL) NOPASSWD: /usr/sbin/service dnsmasq status
www-data ALL=(ALL) NOPASSWD: /usr/sbin/dnsmasq --test</pre>
                <li>Save the file and set permissions: <code>sudo chmod 440 /etc/sudoers.d/www-dnsmasq</code></li>
            </ol>
            <p><strong>Note:</strong> The error you're seeing suggests that the PHP process (www-data) doesn't have the necessary sudo permissions.</p>
        </div>
    <?php endif; ?>

    <div id="command-output" class="command-output<?= !empty($commandOutput) ? ' visible' : '' ?>">
        <strong>Command Output:</strong><?= htmlspecialchars($commandOutput) ?>
    </div>

    <?php if ($plainTextEditMode): ?>
        <div class="edit-form">
            <h3>Edit Configuration File</h3>
            <form method="post" action="" onsubmit="return submitFormAjax(this, 'saveConfig');">
                <div class="form-group">
                    <label for="config_content">Edit /etc/dnsmasq.conf:</label>
                    <textarea id="config_content" name="config_content" rows="20"><?= htmlspecialchars($configContent) ?></textarea>
                </div>
                <div class="buttons">
                    <button type="submit" class="save">Save Configuration</button>
                    <button type="button" class="check" onclick="submitActionAjax('checkConfig')">Check Configuration</button>
                    <button type="button" class="cancel" onclick="window.location.href=window.location.href.split('?')[0]">Cancel</button>
                </div>
            </form>
            <div class="warning" style="margin-top: 15px;"><strong>Warning:</strong> Be careful when editing this file directly. Incorrect syntax may cause DNSMasq to fail.</div>
        </div>
    <?php else: ?>
        <div class="tools-section">
            <button type="button" class="edit" onclick="window.location.href='?action=editConfig'">Edit Configuration File</button>
            <form method="post" action="" style="display: inline-block;" onsubmit="return submitFormAjax(this, 'restart');"><button type="submit" name="action" value="restart">Restart DNSMasq</button></form>
            <form method="post" action="" style="display: inline-block;" onsubmit="return submitFormAjax(this, 'checkConfig');"><button type="submit" name="action" value="checkConfig" class="check">Check Configuration</button></form>
            <button type="button" class="refresh" onclick="refreshTable()">Refresh Table</button>
        </div>

        <form method="post" action="" id="addDomainForm" onsubmit="return submitFormAjax(this, 'add');">
            <div class="form-group"><label for="domain">Domain:</label><input type="text" id="domain" name="domain" placeholder="example.com" required></div>
            <div class="form-group"><label for="type">Type:</label><select id="type" name="type" onchange="toggleRedirectIP(this)">
                    <option value="block">Block</option>
                    <option value="redirect">Redirect</option>
                </select></div>
            <div class="form-group" id="redirect_ip_container" style="display:none"><label for="redirect_ip">Redirect IP:</label><input type="text" id="redirect_ip" name="redirect_ip" placeholder="192.168.1.10"></div>
            <div class="buttons"><button type="submit" name="action" value="add">Add Entry</button></div>
        </form>

        <h2>DNS Entries</h2>
        <?php if (empty($blockedDomains)): ?>
            <p>No domains have been added yet</p>
        <?php else: ?>
            <div class="bulk-actions">
                <input type="checkbox" id="master-checkbox" onchange="toggleAll(this.checked)">
                <label for="master-checkbox">Enable/Disable All</label>
            </div>
            <div class="table-responsive">
                <table id="domains-table">
                    <thead>
                        <tr>
                            <th class="status-column">Status</th>
                            <th>Domain</th>
                            <th>Type</th>
                            <th>Actions</th>
                        </tr>
                    </thead>
                    <tbody><?php foreach ($blockedDomains as $index => $entry) echo generateDomainEntryHtml($index, $entry, $editingDomainId, $changingTypeId); ?></tbody>
                </table>
            </div>
        <?php endif; ?>
    <?php endif; ?>

    <div class="page-info"></div>
</div>
</body>

</html>