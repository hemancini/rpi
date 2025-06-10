<?php
// Start output buffering to prevent any unexpected output
ob_start();

// Set error reporting for debugging but don't display errors directly
ini_set('display_errors', 0);
error_reporting(E_ALL);

// Custom error handler to capture errors in JSON response
function jsonErrorHandler($errno, $errstr, $errfile, $errline)
{
  $error = [
    'status' => 'error',
    'message' => "PHP Error: $errstr in $errfile on line $errline"
  ];

  // Clear any output buffer
  while (ob_get_level()) {
    ob_end_clean();
  }

  // Send JSON response
  header('Content-Type: application/json');
  echo json_encode($error);
  exit;
}

/**
 * Lee una variable específica de un archivo de configuración
 * 
 * @param string $file_path Ruta del archivo de configuración
 * @param string $variable_name Nombre de la variable a buscar
 * @return string|null Valor de la variable o null si no se encuentra
 */
function readConfigVariable($file_path, $variable_name)
{
  // Verificar si el archivo existe
  if (!file_exists($file_path)) {
    // throw new Exception("El archivo $file_path no existe");
    return ""; // Retorna null si el archivo no existe
  }

  // Verificar si el archivo es legible
  if (!is_readable($file_path)) {
    // throw new Exception("No se puede leer el archivo $file_path");
    return "";
  }

  // Leer el contenido del archivo
  $content = file_get_contents($file_path);

  if ($content === false) {
    // throw new Exception("Error al leer el archivo $file_path");
    return "";
  }

  // Buscar la variable usando expresión regular
  $pattern = '/^' . preg_quote($variable_name, '/') . '=(["\']?)(.+?)\1$/m';

  if (preg_match($pattern, $content, $matches)) {
    return $matches[2]; // Retorna el valor sin las comillas
  }

  return null; // Variable no encontrada
}

// Set custom error handler
set_error_handler('jsonErrorHandler');

// Log directory
$logDir = '/var/log/bashrunner/';

// Default starting directory (set to a directory that www-data can access)
$currentDir = isset($_POST['directory']) ? $_POST['directory'] : '/home/pi';

// Get current time
$currentTime = date('Y-m-d H:i:s');

// Get current user
$currentUser = trim(exec('whoami'));


$config_file = '/etc/global_var.conf';
$variable = 'RPI_NETWORK_MODE';

$networkMode = readConfigVariable($config_file, $variable);


// Function to execute command and return output
function executeCommand($command)
{
  global $logDir;

  // Generate a unique log file name based on timestamp
  $logFile = $logDir . 'cmd_' . date('Ymd_His') . '.log';

  // Prepare the sudo command with the bash script
  $sudoCommand = "sudo /bin/bash -c " . escapeshellarg($command . " > $logFile 2>&1 &");

  // Execute the command
  exec($sudoCommand, $output, $returnVar);

  return [
    'status' => $returnVar === 0 ? 'success' : 'error',
    'logFile' => basename($logFile),
    'message' => $returnVar === 0 ? 'Command executed successfully' : 'Error executing command'
  ];
}

// Function to get log content
function getLogContent($logFile)
{
  global $logDir;

  $fullPath = $logDir . $logFile;
  if (file_exists($fullPath)) {
    $command = "sudo /usr/bin/tail -n 100 " . escapeshellarg($fullPath);
    exec($command, $output);
    return implode("\n", $output);
  }
  return "Log file not found";
}

// Function to get all available log files
function getLogFiles()
{
  global $logDir;

  if (!file_exists($logDir)) {
    mkdir($logDir, 0777, true);
  }

  $command = "sudo /bin/ls -t " . escapeshellarg($logDir);
  exec($command, $output);
  return $output;
}

// Function to safely list directory contents using sudo
function listDirectory($directory)
{
  // Sanitize the directory path
  $directory = rtrim($directory, '/');
  if (empty($directory)) $directory = '/';

  // Special case for root directory
  if ($directory === '/') {
    // Get a hardcoded list of common root directories
    $items = [];

    // Add parent directory (not needed for root, but keeps the interface consistent)
    $items[] = [
      'name' => '..',
      'path' => '/',
      'type' => 'directory',
      'isExecutable' => false
    ];

    // Add common root directories
    $rootDirs = [
      'bin',
      'boot',
      'dev',
      'etc',
      'home',
      'lib',
      'media',
      'mnt',
      'opt',
      'proc',
      'root',
      'run',
      'sbin',
      'srv',
      'sys',
      'tmp',
      'usr',
      'var'
    ];

    foreach ($rootDirs as $dir) {
      if (file_exists('/' . $dir)) {
        $items[] = [
          'name' => $dir,
          'path' => '/' . $dir,
          'type' => 'directory',
          'isExecutable' => false
        ];
      }
    }

    return [
      'status' => 'success',
      'currentDirectory' => '/',
      'items' => $items
    ];
  }

  // Use sudo to list the directory contents to bypass permission issues
  $lsCommand = "sudo /bin/ls -la " . escapeshellarg($directory) . " 2>/dev/null";
  exec($lsCommand, $output, $returnVar);

  if ($returnVar !== 0 || empty($output)) {
    // Try an alternative approach for directories with restricted access
    $findCommand = "sudo /usr/bin/find " . escapeshellarg($directory) . " -maxdepth 1 -printf '%y %p\n' 2>/dev/null";
    exec($findCommand, $findOutput, $findReturnVar);

    if ($findReturnVar !== 0 || empty($findOutput)) {
      return [
        'status' => 'error',
        'message' => 'Failed to access directory: ' . $directory
      ];
    }

    // Process the output of find command
    $items = [];

    // Add parent directory
    $parentDir = dirname($directory);
    if ($parentDir === $directory) $parentDir = '/'; // Handle root directory case

    $items[] = [
      'name' => '..',
      'path' => $parentDir,
      'type' => 'directory',
      'isExecutable' => false
    ];

    foreach ($findOutput as $line) {
      $type = substr($line, 0, 1);
      $path = trim(substr($line, 2));
      $name = basename($path);

      // Skip . and .. entries
      if ($name === '.' || $name === '..') {
        continue;
      }

      $isDir = ($type === 'd');
      $isExecutable = (!$isDir && is_executable($path) && preg_match('/\.sh$/', $name));

      $items[] = [
        'name' => $name,
        'path' => $path,
        'type' => $isDir ? 'directory' : 'file',
        'isExecutable' => $isExecutable
      ];
    }

    return [
      'status' => 'success',
      'currentDirectory' => $directory,
      'items' => $items
    ];
  }

  // Process the output of ls command
  $items = [];

  // Add parent directory
  $parentDir = dirname($directory);
  if ($parentDir === $directory) $parentDir = '/'; // Handle root directory case

  $items[] = [
    'name' => '..',
    'path' => $parentDir,
    'type' => 'directory',
    'isExecutable' => false
  ];

  // Process each line from ls command (skip the first line which is total)
  for ($i = 1; $i < count($output); $i++) {
    $line = $output[$i];
    $parts = preg_split('/\s+/', $line, 9);

    if (count($parts) >= 9) {
      $permissions = $parts[0];
      $name = $parts[8];

      // Skip . and .. entries
      if ($name === '.' || $name === '..') {
        continue;
      }

      $path = $directory . '/' . $name;
      $isDir = $permissions[0] === 'd';
      $isExecutable = (!$isDir && ($permissions[3] === 'x' || $permissions[6] === 'x' || $permissions[9] === 'x') && preg_match('/\.sh$/', $name));

      $items[] = [
        'name' => $name,
        'path' => $path,
        'type' => $isDir ? 'directory' : 'file',
        'isExecutable' => $isExecutable
      ];
    }
  }

  return [
    'status' => 'success',
    'currentDirectory' => $directory,
    'items' => $items
  ];
}

// Function to execute a shell script
function executeShellScript($scriptPath)
{
  // Check if the script exists using sudo
  $checkCommand = "sudo /bin/ls " . escapeshellarg($scriptPath) . " 2>/dev/null";
  exec($checkCommand, $output, $returnVar);

  if ($returnVar !== 0 || empty($output)) {
    return [
      'status' => 'error',
      'message' => 'Script does not exist or is not accessible: ' . $scriptPath
    ];
  }

  // Check if it's a shell script
  if (!preg_match('/\.sh$/', $scriptPath)) {
    return [
      'status' => 'error',
      'message' => 'Not a shell script: ' . $scriptPath
    ];
  }

  // Make sure the script is executable
  $chmodCommand = "sudo /bin/chmod +x " . escapeshellarg($scriptPath);
  exec($chmodCommand);

  // Execute the script with sudo
  return executeCommand(escapeshellarg($scriptPath));
}

// Handle AJAX requests
if (isset($_POST['action'])) {
  try {
    // Clear output buffer
    while (ob_get_level()) {
      ob_end_clean();
    }

    header('Content-Type: application/json');

    switch ($_POST['action']) {
      case 'execute':
        if (isset($_POST['command']) && !empty($_POST['command'])) {
          $result = executeCommand($_POST['command']);
          echo json_encode($result);
        } else {
          echo json_encode(['status' => 'error', 'message' => 'No command provided']);
        }
        break;

      case 'getLog':
        if (isset($_POST['logFile']) && !empty($_POST['logFile'])) {
          $content = getLogContent($_POST['logFile']);
          echo json_encode(['status' => 'success', 'content' => $content]);
        } else {
          echo json_encode(['status' => 'error', 'message' => 'No log file specified']);
        }
        break;

      case 'getLogs':
        $logs = getLogFiles();
        echo json_encode(['status' => 'success', 'logs' => $logs]);
        break;

      case 'listDirectory':
        $directory = isset($_POST['directory']) ? $_POST['directory'] : '/home/pi';
        $result = listDirectory($directory);
        echo json_encode($result);
        break;

      case 'executeScript':
        if (isset($_POST['scriptPath']) && !empty($_POST['scriptPath'])) {
          $result = executeShellScript($_POST['scriptPath']);
          echo json_encode($result);
        } else {
          echo json_encode(['status' => 'error', 'message' => 'No script path provided']);
        }
        break;

      default:
        echo json_encode(['status' => 'error', 'message' => 'Invalid action']);
    }
  } catch (Exception $e) {
    echo json_encode([
      'status' => 'error',
      'message' => 'Exception: ' . $e->getMessage()
    ]);
  }

  exit;
}

// For regular page loads, release the buffer
ob_end_flush();
?>

<!DOCTYPE html>
<html lang="en">

<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Raspberry Pi Bash Runner</title>
  <link rel="stylesheet" href="style.css">
</head>

<body>
  <div class="container">
    <h1>Raspberry Pi Bash Runner</h1>
    <div class="user-info">
      <p>Network Mode: <?php echo htmlspecialchars($networkMode); ?></p>
      <p>Current User: <?php echo htmlspecialchars($currentUser); ?></p>
      <p>Current Date: <?php echo htmlspecialchars($currentTime); ?></p>
    </div>

    <div class="command-section">
      <h2>Execute Bash Command</h2>
      <textarea id="command" placeholder="Enter your bash command here..."></textarea>
      <button id="executeBtn">Execute</button>
    </div>

    <div class="file-explorer-section">
      <h2>File Explorer</h2>
      <div class="file-explorer-header">
        <div id="currentPath">/home/pi</div>
        <button id="refreshDirBtn">Refresh</button>
      </div>
      <div class="file-explorer-content" id="fileExplorer">
        <div class="loading">Loading...</div>
      </div>
      <div class="quick-access">
        <button class="quick-access-btn" data-path="/">Root (/)</button>
        <button class="quick-access-btn" data-path="/var/www">Web Root</button>
        <button class="quick-access-btn" data-path="/home">Home</button>
        <button class="quick-access-btn" data-path="/etc">Config</button>
        <button class="quick-access-btn" data-path="/var/log">Logs</button>
      </div>
    </div>

    <div class="log-section">
      <h2>Command Logs</h2>
      <div class="log-controls">
        <select id="logSelect">
          <option value="">Select a log file</option>
        </select>
        <button id="refreshLogsBtn">Refresh Logs</button>
        <button id="autoRefreshBtn">Auto Refresh</button>
      </div>
      <pre id="logOutput">No log selected</pre>
    </div>
  </div>

  <script src="scripts.js"></script>
</body>

</html>