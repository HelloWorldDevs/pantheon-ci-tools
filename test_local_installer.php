<?php

echo "=== LOCAL INSTALLER TEST ===\n";
echo "Testing local code directly (not via Composer package)...\n\n";

$testDir = __DIR__ . '/sampleoutput';
$originalDir = getcwd();

// Clean up any existing test directory
if (is_dir($testDir)) {
    echo "Cleaning up existing test directory...\n";
    exec("rm -rf " . escapeshellarg($testDir));
}

// Create test project directory
mkdir($testDir, 0755, true);
echo "Created test directory: $testDir\n";

// Create test project structure based on platform argument
$platform = $argv[1] ?? 'pantheon';
$framework = $argv[2] ?? 'laravel';

echo "Testing platform: $platform, framework: $framework\n\n";

// Create platform marker files
switch ($platform) {
    case 'pantheon':
        file_put_contents($testDir . '/pantheon.yml', "api_version: 1\nweb_docroot: true\n");
        echo "Created pantheon.yml marker\n";
        break;
    case 'upsun':
        mkdir($testDir . '/.upsun', 0755, true);
        file_put_contents($testDir . '/.upsun/config.yaml', "applications:\n  app:\n    type: php:8.2\n");
        echo "Created .upsun/ marker\n";
        break;
    case 'wpengine':
        file_put_contents($testDir . '/.wpengine-marker', '');
        echo "Created .wpengine-marker\n";
        break;
}

// Create framework marker files
switch ($framework) {
    case 'drupal':
        mkdir($testDir . '/web/core', 0755, true);
        file_put_contents($testDir . '/web/core/drupal.php', '<?php // Drupal core');
        echo "Created web/core/ marker for Drupal\n";
        break;
    case 'wordpress':
        file_put_contents($testDir . '/wp-config.php', '<?php // WordPress config');
        echo "Created wp-config.php marker\n";
        break;
    case 'laravel':
        file_put_contents($testDir . '/artisan', '#!/usr/bin/env php');
        chmod($testDir . '/artisan', 0755);
        echo "Created artisan marker for Laravel\n";
        break;
}

// Create a simple composer.json
$mockComposerJson = [
    "name" => "test/$framework-project",
    "type" => "project",
    "description" => "Test $framework project for local installer testing",
    "require" => [
        "php" => ">=8.1"
    ]
];

file_put_contents($testDir . '/composer.json', json_encode($mockComposerJson, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
echo "Created composer.json\n\n";

// Include our local classes BEFORE changing directories
echo "Running LOCAL installer code directly...\n";
echo "==========================================\n\n";

require_once __DIR__ . '/vendor/autoload.php';

// Now change to test directory
chdir($testDir);
echo "Changed to test directory\n\n";

use HelloWorldDevs\CI\Installer;
use Composer\IO\ConsoleIO;
use Symfony\Component\Console\Helper\HelperSet;
use Symfony\Component\Console\Input\ArgvInput;
use Symfony\Component\Console\Output\ConsoleOutput;

try {
    // Create a Composer IO
    $input = new ArgvInput();
    $output = new ConsoleOutput();
    $helperSet = new HelperSet();
    $io = new ConsoleIO($input, $output, $helperSet);

    echo "Running Installer::install()...\n\n";

    // Run the installer directly
    $installer = new Installer($io);
    $installer->install();

    echo "\n\nFirst run completed!\n\n";

    // Run the installer AGAIN to test idempotency
    echo "Running installer SECOND TIME to test idempotency...\n";
    echo "====================================================\n\n";

    $installer2 = new Installer($io);
    $installer2->install();

    echo "\n\nSecond run completed!\n\n";

} catch (Exception $e) {
    echo "Error running installer: " . $e->getMessage() . "\n";
    echo "Stack trace:\n" . $e->getTraceAsString() . "\n\n";
}

// Check what files were created
echo "\n";
echo "Files created in test directory:\n";
echo "===================================\n";
exec('find . -type f | grep -v "^\./\." | head -30', $files);
foreach ($files as $file) {
    echo "$file\n";
}

echo "\n";
echo "Directories created:\n";
echo "===================================\n";
exec('find . -type d | grep -v "^\./\." | head -20', $dirs);
foreach ($dirs as $dir) {
    echo "$dir\n";
}

// Check for key files
echo "\n";
echo "Key files check:\n";
echo "===================================\n";

$keyFiles = [
    '.github/workflows/vrt.yml' => 'VRT GitHub Action',
    '.ci/test/visual-regression/run-playwright' => 'VRT runner script',
    '.ci/test/visual-regression/update-baselines' => 'Baseline update script',
    '.gitattributes' => 'Git LFS tracking',
];

foreach ($keyFiles as $file => $desc) {
    $exists = file_exists($file);
    echo "  $desc: " . ($exists ? "YES" : "NO") . " ($file)\n";
}

// Check .gitattributes content
if (file_exists('.gitattributes')) {
    echo "\n";
    echo ".gitattributes content:\n";
    echo "===================================\n";
    echo file_get_contents('.gitattributes');
}

// Return to original directory
chdir($originalDir);

echo "\n";
echo "LOCAL installer test completed!\n";
echo "   Check the sampleoutput directory for results.\n";
echo "   To clean up: rm -rf sampleoutput\n";
echo "\n";
echo "Usage: php test_local_installer.php [platform] [framework]\n";
echo "   Platforms: pantheon, upsun, wpengine\n";
echo "   Frameworks: drupal, wordpress, laravel\n";