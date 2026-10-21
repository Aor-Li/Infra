{
  den.aspects.dev.shell.multiplexer.tmux.homeManager =
    { pkgs, ... }:
    {
      programs.tmux = {
        enable = true;

        # basic settings
        clock24 = true;
        baseIndex = 1;
        mouse = true;

        # Stop tmux+escape craziness. 0 会让部分终端把 Alt 组合键当成 ESC 序列拆开，
        # 50ms 是上限体验和 Alt 键可靠性之间的折中。
        escapeTime = 50;

        # Force tmux to use /tmp for sockets (WSL2 compat)
        secureSocket = false;

        # add plugins
        # 配色由 stylix 生成（system/theme.nix），这里不再装主题插件
        plugins = with pkgs.tmuxPlugins; [
          cpu
          battery
          yank
        ];

        # configuration file
        extraConfig = ''
          # bash
          ###################################################################
          ###  Basic Function Settings                                    ###
          ###################################################################
          # do not rename window automaticly
          set-option -g allow-rename off
          # renumber when window closed
          set -g renumber-window on
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
          # --- status bar ---
          set-option -g status-position top
          set -g status-right-length 100
          set -g status-left-length 100
          set -g status-left ""
          set -g window-status-format " #I #W "
          set -g window-status-current-format " #I #W "
          set -g status-right " #{pane_current_command} │ CPU #{cpu_percentage} │ #S │ #{battery_icon} #{battery_percentage} "
          run-shell ${pkgs.tmuxPlugins.cpu}/share/tmux-plugins/cpu/cpu.tmux
          run-shell ${pkgs.tmuxPlugins.battery}/share/tmux-plugins/battery/battery.tmux
        '';
      };
    };
}
