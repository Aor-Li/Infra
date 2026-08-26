{ ... }:
{
  den.aspects.dev.shell.multiplexer.tmux.homeManager =
    { pkgs, ... }:
    {
      programs.tmux = {
        enable = true;

        # tmux 3.7c's configure script requires an explicit jemalloc choice on
        # Darwin (macOS calloc(3) doesn't reliably zero allocations); upstream
        # nixpkgs doesn't pass either flag yet, so builds from source fail.
        # https://github.com/tmux/tmux/commit/(jemalloc detection change)
        package = pkgs.tmux.overrideAttrs (old: {
          configureFlags = old.configureFlags ++ [ "--disable-jemalloc" ];
        });

        # basic settings
        clock24 = true;
        baseIndex = 1;

        # Stop tmux+escape craziness.
        escapeTime = 0;

        # Force tmux to use /tmp for sockets (WSL2 compat)
        secureSocket = false;

        # add plugins
        plugins = with pkgs.tmuxPlugins; [
          catppuccin
          cpu
          battery
        ];

        # configuration file
        extraConfig = ''
          # bash
          ###################################################################
          ###  Basic Function Settings                                    ###
          ###################################################################
          set-option -g mouse on
          # do not rename window automaticly
          set-option -g allow-rename off
          # renumber when window closed
          set -g renumber-window on
          set -sg escape-time 100
          ###################################################################
          ###  Basic KeyBinds Settings                                    ###
          ###################################################################
          bind r source-file ~/.config/tmux/tmux.conf # reload config
          bind c new-window -c "#{pane_current_path}"
          bind | split-window -h -c "#{pane_current_path}"
          bind - split-window -v -c "#{pane_current_path}"
          bind '"' split-window -v -c "#{pane_current_path}"
          bind % split-window -h -c "#{pane_current_path}"
          ###################################################################
          ###  Appearance Settings                                        ###
          ###################################################################
          # --- colors ---
          # (https://old.reddit.com/r/tmux/comments/mesrci/tmux_2_doesnt_seem_to_use_256_colors/)
          set -g default-terminal "xterm-256color"
          set -ga terminal-overrides ",*256col*:Tc"
          set -ga terminal-overrides '*:Ss=\E[%p1%d q:Se=\E[ q'
          set-environment -g COLORTERM "truecolor"
          # --- themes: catppuccin ---
          set -g @catppuccin_flavor "mocha"
          set -g @catppuccin_window_status_style "slanted" # idk why but rounded not work for me
          set -g @catppuccin_window_default_text "#W"
          set -g @catppuccin_window_current_text "#W"
          set -g @catppuccin_window_text "#W"
          # --- status bar ---
          set-option -g status-position top
          run-shell ${pkgs.tmuxPlugins.catppuccin}/share/tmux-plugins/catppuccin/catppuccin.tmux
          set -g status-right-length 100
          set -g status-left-length 100
          set -g status-left ""
          set -g status-right "#{E:@catppuccin_status_application}"
          set -agF status-right "#{E:@catppuccin_status_cpu}"
          set -ag status-right "#{E:@catppuccin_status_session}"
          set -ag status-right "#{E:@catppuccin_status_uptime}"
          set -agF status-right "#{E:@catppuccin_status_battery}"
          run-shell ${pkgs.tmuxPlugins.cpu}/share/tmux-plugins/cpu/cpu.tmux
          run-shell ${pkgs.tmuxPlugins.battery}/share/tmux-plugins/battery/battery.tmux
          # plugins: yank
        '';
      };
    };
}
