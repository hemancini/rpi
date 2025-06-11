<?php
// Definir la ruta base para construir URLs correctamente
$baseUrl = '';

// Obtener el nombre del archivo actual para resaltar el enlace activo
$currentPage = basename($_SERVER['SCRIPT_NAME']);
?>

<!DOCTYPE html>
<html lang="es">

<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    /* Estilos para el app bar */
    .app-bar {
      background-color: #2c3e50;
      overflow: hidden;
      box-shadow: 0 2px 5px rgba(0, 0, 0, 0.2);
      /* position: sticky; */
      top: 0;
      width: 100%;
      z-index: 1000;
    }

    .app-bar ul {
      margin: 0;
      padding: 0;
      list-style-type: none;
      display: flex;
    }

    .app-bar li {
      margin: 0;
      padding: 0;
    }

    .app-bar a {
      color: white;
      text-decoration: none;
      padding: 16px 20px;
      display: block;
      transition: background-color 0.3s;
    }

    .app-bar a:hover {
      background-color: #34495e;
    }

    .app-bar a.active {
      background-color: #3498db;
      font-weight: bold;
    }

    /* Nombre del usuario */
    .user-info {
      margin-left: auto;
      color: #ecf0f1;
      padding: 16px 20px;
    }
  </style>
</head>

<body>
  <div class="app-bar">
    <ul>
      <li><a href="<?php echo $baseUrl; ?>/index.php" <?php if ($currentPage == 'index.php') echo 'class="active"'; ?>>Bash</a></li>
      <li><a href="<?php echo $baseUrl; ?>/dnsmasq.php" <?php if ($currentPage == 'dnsmasq.php') echo 'class="active"'; ?>>Dnsmasq</a></li>
      <li><a href="<?php echo $baseUrl; ?>/wifi.php" <?php if ($currentPage == 'wifi.php') echo 'class="active"'; ?>>WiFi</a></li>
      <li style="flex-grow: 1;"></li>
      <li><a href="<?php echo $baseUrl; ?>/ps4.html" <?php if ($currentPage == 'ps4.html') echo 'class="active"'; ?>>PS4</a></li>
    </ul>
  </div>