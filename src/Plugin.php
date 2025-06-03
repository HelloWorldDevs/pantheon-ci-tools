<?php

namespace HelloWorldDevs\PantheonCI;

use Composer\Composer;
use Composer\EventDispatcher\EventSubscriberInterface;
use Composer\IO\IOInterface;
use Composer\Plugin\PluginInterface;
use Composer\Script\Event;
use Composer\Script\ScriptEvents;

class Plugin implements PluginInterface, EventSubscriberInterface
{
    /**
     * @var Composer
     */
    protected $composer;

    /**
     * @var IOInterface
     */
    protected $io;

    /**
     * {@inheritDoc}
     */
    public function activate(Composer $composer, IOInterface $io)
    {
        $this->composer = $composer;
        $this->io = $io;
    }

    /**
     * {@inheritDoc}
     */
    public function deactivate(Composer $composer, IOInterface $io)
    {
        // Nothing to do here
    }

    /**
     * {@inheritDoc}
     */
    public function uninstall(Composer $composer, IOInterface $io)
    {
        // Nothing to do here
    }

    /**
     * {@inheritDoc}
     */
    public static function getSubscribedEvents()
    {
        return [
            ScriptEvents::POST_INSTALL_CMD => 'onPostInstallUpdate',
            ScriptEvents::POST_UPDATE_CMD => 'onPostInstallUpdate',
        ];
    }

    /**
     * Handle post install/update events
     *
     * @param Event $event
     */
    public function onPostInstallUpdate(Event $event)
    {
        $this->io->write('<info>Pantheon CI Tools: Installing CI configuration files...</info>');
        
        try {
            $installer = new Installer($this->io);
            $installer->install();
            
            $this->io->write('<info>✓ Pantheon CI Tools: Installation complete!</info>');
        } catch (\Exception $e) {
            $this->io->writeError(sprintf(
                '<error>Error installing Pantheon CI Tools: %s</error>',
                $e->getMessage()
            ));
            throw $e;
        }
    }
}
