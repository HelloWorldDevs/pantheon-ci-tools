<?php

namespace HelloWorldDevs\CI;

use Composer\Composer;
use Composer\EventDispatcher\EventSubscriberInterface;
use Composer\IO\IOInterface;
use Composer\Plugin\PluginInterface;
use Composer\Script\Event;
use Composer\Script\ScriptEvents;

class Plugin implements PluginInterface, EventSubscriberInterface
{
    protected Composer $composer;
    protected IOInterface $io;

    public function activate(Composer $composer, IOInterface $io): void
    {
        $this->composer = $composer;
        $this->io = $io;
    }

    public function deactivate(Composer $composer, IOInterface $io): void
    {
        // Nothing to do here
    }

    public function uninstall(Composer $composer, IOInterface $io): void
    {
        // Nothing to do here
    }

    public static function getSubscribedEvents(): array
    {
        return [
            ScriptEvents::POST_INSTALL_CMD => 'onPostInstallUpdate',
            ScriptEvents::POST_UPDATE_CMD => 'onPostInstallUpdate',
        ];
    }

    public function onPostInstallUpdate(Event $event): void
    {
        $this->io->write('<info>HWD CI Tools: Installing CI configuration files...</info>');

        try {
            // Get config from composer.json extra section (the Composer way)
            $extra = $this->composer->getPackage()->getExtra();
            $ciToolsConfig = $extra['ci-tools'] ?? null;

            $installer = new Installer($this->io, $ciToolsConfig);
            $installer->install();

            $this->io->write('<info>HWD CI Tools: Installation complete!</info>');
        } catch (\Exception $e) {
            $this->io->writeError(sprintf(
                '<error>Error installing HWD CI Tools: %s</error>',
                $e->getMessage()
            ));
            throw $e;
        }
    }

    /**
     * Static method to run installer manually via: composer ci-tools:install
     * Use --force to overwrite existing template files
     */
    public static function runInstall(Event $event): void
    {
        $io = $event->getIO();
        $composer = $event->getComposer();

        // Check for --force argument
        $args = $event->getArguments();
        $force = in_array('--force', $args, true);

        if ($force) {
            $io->write('<info>HWD CI Tools: Force mode - will overwrite existing files...</info>');
        }

        $io->write('<info>HWD CI Tools: Installing CI configuration files...</info>');

        try {
            $extra = $composer->getPackage()->getExtra();
            $ciToolsConfig = $extra['ci-tools'] ?? null;

            $installer = new Installer($io, $ciToolsConfig, $force);
            $installer->install();

            $io->write('<info>HWD CI Tools: Installation complete!</info>');
        } catch (\Exception $e) {
            $io->writeError(sprintf(
                '<error>Error installing HWD CI Tools: %s</error>',
                $e->getMessage()
            ));
            throw $e;
        }
    }
}
