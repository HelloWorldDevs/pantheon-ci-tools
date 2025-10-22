<?php

echo "=== LOCAL INSTALLER TEST ===\n";
echo "Testing local code directly (not via Composer package)...\n\n";

$testDir = __DIR__ . '/sampleoutput';
$originalDir = getcwd();

// Clean up any existing test directory
if (is_dir($testDir)) {
    echo "🧹 Cleaning up existing test directory...\n";
    exec("rm -rf " . escapeshellarg($testDir));
}

// Create test project directory
mkdir($testDir, 0755, true);
echo "📁 Created test directory: $testDir\n";

// Copy our sample lando file to the test directory
copy(__DIR__ . '/lando-test.yml', $testDir . '/.lando.yml');
echo "📋 Copied sample .lando.yml to test directory\n";

// Create a simple composer.json (no need for our package)
$mockComposerJson = [
    "name" => "test/drupal-project",
    "type" => "project",
    "description" => "Test Drupal project for local installer testing",
    "require" => [
        "php" => ">=8.1",
        "drupal/core" => "^10.0"
    ]
];

file_put_contents($testDir . '/composer.json', json_encode($mockComposerJson, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
echo "📦 Created simple composer.json\n";

// Show original .lando.yml before changing directories
echo "\n📄 Original .lando.yml (first 20 lines):\n";
echo "=========================================\n";
$originalLando = file_get_contents($testDir . '/.lando.yml');
$originalLines = explode("\n", $originalLando);
for ($i = 0; $i < min(20, count($originalLines)); $i++) {
    echo ($i + 1) . ": " . $originalLines[$i] . "\n";
}
echo "... (total " . count($originalLines) . " lines)\n\n";

// Include our local classes BEFORE changing directories
echo "🚀 Running LOCAL installer code directly...\n";
echo "==========================================\n";

require_once __DIR__ . '/vendor/autoload.php';  // For Symfony YAML and Composer classes

// Manually include our source files since we're not using Composer autoloading
require_once __DIR__ . '/src/Installer.php';
require_once __DIR__ . '/src/InstallConfigSplit.php';
require_once __DIR__ . '/src/Plugin.php';

// Now change to test directory
chdir($testDir);
echo "📂 Changed to test directory\n";

use HelloWorldDevs\PantheonCI\Installer;
use HelloWorldDevs\PantheonCI\InstallConfigSplit;
use Composer\IO\ConsoleIO;
use Symfony\Component\Console\Helper\HelperSet;
use Symfony\Component\Console\Input\ArgvInput;
use Symfony\Component\Console\Output\ConsoleOutput;

try {
    // Create a mock Composer IO
    $input = new ArgvInput();
    $output = new ConsoleOutput();
    $helperSet = new HelperSet();
    $io = new ConsoleIO($input, $output, $helperSet);
    
    echo "📦 Running Installer::install()...\n";
    
    // Run the installer directly
    $installer = new Installer($io);
    $result = $installer->install();
    
    if ($result) {
        echo "✅ Installer completed successfully!\n\n";
    } else {
        echo "❌ Installer reported failure\n\n";
    }
    
} catch (Exception $e) {
    echo "❌ Error running installer: " . $e->getMessage() . "\n";
    echo "Stack trace:\n" . $e->getTraceAsString() . "\n\n";
}

// Check if .lando.yml was modified
if (file_exists('.lando.yml')) {
    $modifiedLando = file_get_contents('.lando.yml');
    
    echo "📄 Modified .lando.yml (last 30 lines):\n";
    echo "=======================================\n";
    $modifiedLines = explode("\n", $modifiedLando);
    $startLine = max(0, count($modifiedLines) - 30);
    for ($i = $startLine; $i < count($modifiedLines); $i++) {
        echo ($i + 1) . ": " . $modifiedLines[$i] . "\n";
    }
    echo "=======================================\n\n";
    
    // Analysis
    echo "🔍 Analysis:\n";
    echo "============\n";
    
    $originalLineCount = count($originalLines);
    $modifiedLineCount = count($modifiedLines);
    
    echo "Original lines: $originalLineCount\n";
    echo "Modified lines: $modifiedLineCount\n";
    echo "Lines added: " . ($modifiedLineCount - $originalLineCount) . "\n\n";
    
    // Check for our additions
    $foundDevConfig = strpos($modifiedLando, 'dev-config:') !== false;
    $foundConfigCheck = strpos($modifiedLando, 'config-check:') !== false;
    $foundSafeExport = strpos($modifiedLando, 'safe-export:') !== false;
    $foundPostStartEvent = strpos($modifiedLando, 'bash /app/lando/scripts/dev-config.sh enable') !== false;
    $foundPostPullEvent = strpos($modifiedLando, 'bash /app/lando/scripts/dev-config.sh disable') !== false;
    
    echo "✅ Tooling commands added:\n";
    echo "  - dev-config: " . ($foundDevConfig ? "✅" : "❌") . "\n";
    echo "  - config-check: " . ($foundConfigCheck ? "✅" : "❌") . "\n";
    echo "  - safe-export: " . ($foundSafeExport ? "✅" : "❌") . "\n\n";
    
    echo "✅ Events added:\n";
    echo "  - post-start dev setup: " . ($foundPostStartEvent ? "✅" : "❌") . "\n";
    echo "  - post-pull dev disable: " . ($foundPostPullEvent ? "✅" : "❌") . "\n\n";
    
    // Check for formatting issues
    $hasQuotedCommands = strpos($modifiedLando, "'appserver:") !== false;
    $hasLineBreakIssues = preg_match("/- \n\s+appserver:/", $modifiedLando);
    
    echo "✅ YAML formatting:\n";
    echo "  - No quoted appserver commands: " . ($hasQuotedCommands ? "❌" : "✅") . "\n";
    echo "  - No line break issues: " . ($hasLineBreakIssues ? "❌" : "✅") . "\n\n";
    
    // Check if scripts were installed
    $scriptsInstalled = is_dir('lando/scripts') && 
                       file_exists('lando/scripts/dev-config.sh') && 
                       file_exists('lando/scripts/config-safety-check.sh');
    
    echo "✅ Scripts installed:\n";
    echo "  - lando/scripts directory: " . (is_dir('lando/scripts') ? "✅" : "❌") . "\n";
    echo "  - dev-config.sh: " . (file_exists('lando/scripts/dev-config.sh') ? "✅" : "❌") . "\n";
    echo "  - config-safety-check.sh: " . (file_exists('lando/scripts/config-safety-check.sh') ? "✅" : "❌") . "\n\n";
    
    // Check CI files
    $ciFilesInstalled = is_dir('.circleci') && 
                       file_exists('.circleci/config.yml') && 
                       is_dir('.ci/scripts');
    
    echo "✅ CI files installed:\n";
    echo "  - .circleci directory: " . (is_dir('.circleci') ? "✅" : "❌") . "\n";
    echo "  - .ci/scripts directory: " . (is_dir('.ci/scripts') ? "✅" : "❌") . "\n";
    echo "  - CircleCI config: " . (file_exists('.circleci/config.yml') ? "✅" : "❌") . "\n\n";
    
    // Overall success
    $allToolingAdded = $foundDevConfig && $foundConfigCheck && $foundSafeExport;
    $allEventsAdded = $foundPostStartEvent && $foundPostPullEvent;
    $goodFormatting = !$hasQuotedCommands && !$hasLineBreakIssues;
    
    if ($allToolingAdded && $allEventsAdded && $goodFormatting && $scriptsInstalled && $ciFilesInstalled) {
        echo "🎉 SUCCESS! All modifications applied correctly by LOCAL code!\n";
    } else {
        echo "⚠️  Some issues found - check the analysis above\n";
    }
    
} else {
    echo "❌ .lando.yml file not found after installation\n";
}

// Check what files were created
echo "\n📁 Files created in test directory:\n";
echo "===================================\n";
exec('find . -name "*.yml" -o -name "*.sh" -o -name "*.js" | head -15', $files);
foreach ($files as $file) {
    echo "$file\n";
}

// Return to original directory
chdir($originalDir);

echo "\n💡 LOCAL installer test completed!\n";
echo "   This test ran your actual local code, not a Composer package.\n";
echo "   Check the sampleoutput directory for results.\n";
echo "   To clean up: rm -rf sampleoutput\n";
