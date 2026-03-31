classdef SDRRadioApp < matlab.apps.AppBase

    % ---------------------------------------------------------------
    %  SDR Radio App
    %  Requires MATLAB R2021a+ with App Designer runtime.
    %  Calls sdr_transmit(src_call, dst_call, message) and
    %       sdr_receive() -> struct with fields .src, .dst, .message
    % ---------------------------------------------------------------

    properties (Access = public)
        UIFigure            matlab.ui.Figure

        % ── Layout panels ──────────────────────────────────────────
        HeaderPanel         matlab.ui.container.Panel
        ControlPanel        matlab.ui.container.Panel
        LogPanel            matlab.ui.container.Panel

        % ── Header ─────────────────────────────────────────────────
        TitleLabel          matlab.ui.control.Label
        StatusLabel         matlab.ui.control.Label

        % ── Callsign / message inputs ───────────────────────────────
        SrcCallLabel        matlab.ui.control.Label
        SrcCallField        matlab.ui.control.EditField
        DstCallLabel        matlab.ui.control.Label
        DstCallField        matlab.ui.control.EditField
        MessageLabel        matlab.ui.control.Label
        MessageArea         matlab.ui.control.TextArea

        % ── Buttons ─────────────────────────────────────────────────
        TransmitButton      matlab.ui.control.Button
        ReceiveToggle       matlab.ui.control.StateButton

        % ── Receive log ─────────────────────────────────────────────
        LogLabel            matlab.ui.control.Label
        LogArea             matlab.ui.control.TextArea
        ClearLogButton      matlab.ui.control.Button

        % ── Timer ───────────────────────────────────────────────────
        RxTimer             timer
    end

    % ================================================================
    %  App initialisation
    % ================================================================
    methods (Access = private)

        function createComponents(app)

            % ── Figure ───────────────────────────────────────────────
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position  = [100 100 520 660];
            app.UIFigure.Name      = 'SDR Radio Terminal';
            app.UIFigure.Color     = [0.08 0.09 0.10];
            app.UIFigure.Resize    = 'off';

            % ── Header panel ─────────────────────────────────────────
            app.HeaderPanel = uipanel(app.UIFigure);
            app.HeaderPanel.BackgroundColor = [0.10 0.12 0.14];
            app.HeaderPanel.BorderType      = 'none';
            app.HeaderPanel.Position        = [0 600 520 60];

            app.TitleLabel = uilabel(app.HeaderPanel);
            app.TitleLabel.Text              = '⊿  SDR RADIO TERMINAL';
            app.TitleLabel.FontName          = 'Courier New';
            app.TitleLabel.FontSize          = 16;
            app.TitleLabel.FontWeight        = 'bold';
            app.TitleLabel.FontColor         = [0.18 0.85 0.50];
            app.TitleLabel.Position          = [16 14 280 30];

            app.StatusLabel = uilabel(app.HeaderPanel);
            app.StatusLabel.Text             = '● IDLE';
            app.StatusLabel.FontName         = 'Courier New';
            app.StatusLabel.FontSize         = 12;
            app.StatusLabel.FontWeight       = 'bold';
            app.StatusLabel.FontColor        = [0.55 0.55 0.55];
            app.StatusLabel.HorizontalAlignment = 'right';
            app.StatusLabel.Position         = [300 14 204 30];

            % ── Control panel ────────────────────────────────────────
            app.ControlPanel = uipanel(app.UIFigure);
            app.ControlPanel.BackgroundColor = [0.10 0.12 0.14];
            app.ControlPanel.BorderType      = 'none';
            app.ControlPanel.Position        = [0 350 520 248];

            % Source callsign
            app.SrcCallLabel = uilabel(app.ControlPanel);
            app.SrcCallLabel.Text       = 'SOURCE CALLSIGN';
            app.SrcCallLabel.FontName   = 'Courier New';
            app.SrcCallLabel.FontSize   = 10;
            app.SrcCallLabel.FontColor  = [0.45 0.55 0.50];
            app.SrcCallLabel.Position   = [20 200 160 18];

            app.SrcCallField = uieditfield(app.ControlPanel, 'text');
            app.SrcCallField.Value       = 'KD9XYZ';
            app.SrcCallField.FontName    = 'Courier New';
            app.SrcCallField.FontSize    = 13;
            app.SrcCallField.FontColor   = [0.18 0.85 0.50];
            app.SrcCallField.BackgroundColor = [0.06 0.08 0.09];
            app.SrcCallField.Position    = [20 174 210 26];

            % Destination callsign
            app.DstCallLabel = uilabel(app.ControlPanel);
            app.DstCallLabel.Text       = 'DESTINATION CALLSIGN';
            app.DstCallLabel.FontName   = 'Courier New';
            app.DstCallLabel.FontSize   = 10;
            app.DstCallLabel.FontColor  = [0.45 0.55 0.50];
            app.DstCallLabel.Position   = [270 200 220 18];

            app.DstCallField = uieditfield(app.ControlPanel, 'text');
            app.DstCallField.Value       = 'W1AW';
            app.DstCallField.FontName    = 'Courier New';
            app.DstCallField.FontSize    = 13;
            app.DstCallField.FontColor   = [0.18 0.85 0.50];
            app.DstCallField.BackgroundColor = [0.06 0.08 0.09];
            app.DstCallField.Position    = [270 174 230 26];

            % Message
            app.MessageLabel = uilabel(app.ControlPanel);
            app.MessageLabel.Text       = 'MESSAGE';
            app.MessageLabel.FontName   = 'Courier New';
            app.MessageLabel.FontSize   = 10;
            app.MessageLabel.FontColor  = [0.45 0.55 0.50];
            app.MessageLabel.Position   = [20 142 160 18];

            app.MessageArea = uitextarea(app.ControlPanel);
            app.MessageArea.Value            = {''};
            app.MessageArea.FontName         = 'Courier New';
            app.MessageArea.FontSize         = 12;
            app.MessageArea.FontColor        = [0.90 0.92 0.88];
            app.MessageArea.BackgroundColor  = [0.06 0.08 0.09];
            app.MessageArea.Position         = [20 68 480 72];

            % ── Transmit button ──────────────────────────────────────
            app.TransmitButton = uibutton(app.ControlPanel, 'push');
            app.TransmitButton.Text              = '▶  TRANSMIT';
            app.TransmitButton.FontName          = 'Courier New';
            app.TransmitButton.FontSize          = 13;
            app.TransmitButton.FontWeight        = 'bold';
            app.TransmitButton.FontColor         = [0.05 0.05 0.05];
            app.TransmitButton.BackgroundColor   = [0.18 0.85 0.50];
            app.TransmitButton.Position          = [20 20 220 38];
            app.TransmitButton.ButtonPushedFcn   = @(~,~) app.onTransmit();

            % ── Receive toggle button ────────────────────────────────
            app.ReceiveToggle = uibutton(app.ControlPanel, 'state');
            app.ReceiveToggle.Text              = '◉  START LISTENING';
            app.ReceiveToggle.FontName          = 'Courier New';
            app.ReceiveToggle.FontSize          = 13;
            app.ReceiveToggle.FontWeight        = 'bold';
            app.ReceiveToggle.FontColor         = [0.90 0.92 0.88];
            app.ReceiveToggle.BackgroundColor   = [0.16 0.20 0.22];
            app.ReceiveToggle.Position          = [280 20 220 38];
            app.ReceiveToggle.ValueChangedFcn   = @(src,~) app.onReceiveToggle(src);

            % Divider (simulated with a thin panel)
            divider = uipanel(app.UIFigure);
            divider.BackgroundColor = [0.18 0.85 0.50];
            divider.BorderType      = 'none';
            divider.Position        = [0 349 520 2];

            % ── Log panel ────────────────────────────────────────────
            app.LogPanel = uipanel(app.UIFigure);
            app.LogPanel.BackgroundColor = [0.08 0.09 0.10];
            app.LogPanel.BorderType      = 'none';
            app.LogPanel.Position        = [0 0 520 348];

            app.LogLabel = uilabel(app.LogPanel);
            app.LogLabel.Text       = 'RECEIVED MESSAGES';
            app.LogLabel.FontName   = 'Courier New';
            app.LogLabel.FontSize   = 10;
            app.LogLabel.FontColor  = [0.45 0.55 0.50];
            app.LogLabel.Position   = [20 316 240 18];

            app.ClearLogButton = uibutton(app.LogPanel, 'push');
            app.ClearLogButton.Text            = 'CLEAR';
            app.ClearLogButton.FontName        = 'Courier New';
            app.ClearLogButton.FontSize        = 10;
            app.ClearLogButton.FontColor       = [0.55 0.55 0.55];
            app.ClearLogButton.BackgroundColor = [0.12 0.14 0.16];
            app.ClearLogButton.Position        = [420 312 80 22];
            app.ClearLogButton.ButtonPushedFcn = @(~,~) app.clearLog();

            app.LogArea = uitextarea(app.LogPanel);
            app.LogArea.Editable         = 'off';
            app.LogArea.Value            = {'[SDR Radio Terminal ready]'};
            app.LogArea.FontName         = 'Courier New';
            app.LogArea.FontSize         = 11;
            app.LogArea.FontColor        = [0.18 0.85 0.50];
            app.LogArea.BackgroundColor  = [0.05 0.06 0.07];
            app.LogArea.Position         = [10 10 500 300];

            % ── Show figure ──────────────────────────────────────────
            app.UIFigure.Visible = 'on';
        end
    end

    % ================================================================
    %  Callbacks
    % ================================================================
    methods (Access = private)

        % ── TRANSMIT ─────────────────────────────────────────────────
        function onTransmit(app)
            src = strtrim(app.SrcCallField.Value);
            dst = strtrim(app.DstCallField.Value);
            msg = strjoin(app.MessageArea.Value, newline);

            if isempty(src) || isempty(dst)
                app.appendLog('[ERROR] Source and destination callsigns are required.');
                return
            end
            if isempty(strtrim(msg))
                app.appendLog('[ERROR] Message is empty.');
                return
            end

            app.setStatus('TRANSMITTING', [0.95 0.75 0.10]);
            app.TransmitButton.Enable = 'off';
            drawnow;

            try
                sdr_transmit(src, dst, msg);
                app.appendLog(sprintf('[TX] %s → %s : %s', src, dst, msg));
            catch ex
                app.appendLog(sprintf('[TX ERROR] %s', ex.message));
            end

            app.TransmitButton.Enable = 'on';
            if ~app.ReceiveToggle.Value
                app.setStatus('IDLE', [0.55 0.55 0.55]);
            else
                app.setStatus('LISTENING', [0.20 0.65 0.95]);
            end
        end

        % ── RECEIVE TOGGLE ───────────────────────────────────────────
        function onReceiveToggle(app, btn)
            if btn.Value
                % Start listening
                app.ReceiveToggle.Text            = '■  STOP LISTENING';
                app.ReceiveToggle.BackgroundColor = [0.10 0.25 0.40];
                app.ReceiveToggle.FontColor       = [0.20 0.65 0.95];
                app.setStatus('LISTENING', [0.20 0.65 0.95]);

                app.RxTimer = timer( ...
                    'ExecutionMode', 'fixedRate', ...
                    'Period',        2.0, ...
                    'TimerFcn',      @(~,~) app.pollReceive());
                start(app.RxTimer);
                app.appendLog('[RX] Listening started (polling every 2 s)…');
            else
                % Stop listening
                app.stopTimer();
                app.ReceiveToggle.Text            = '◉  START LISTENING';
                app.ReceiveToggle.BackgroundColor = [0.16 0.20 0.22];
                app.ReceiveToggle.FontColor       = [0.90 0.92 0.88];
                app.setStatus('IDLE', [0.55 0.55 0.55]);
                app.appendLog('[RX] Listening stopped.');
            end
        end

        % ── TIMER CALLBACK ───────────────────────────────────────────
        function pollReceive(app)
            try
                result = sdr_receive();
                if ~isempty(result)
                    if isstruct(result)
                        % Handle array of decoded packets
                        for k = 1:numel(result)
                            r = result(k);
                            src = app.safeField(r, 'src', '???');
                            dst = app.safeField(r, 'dst', '???');
                            msg = app.safeField(r, 'message', '(empty)');
                            app.appendLog(sprintf('[RX] %s → %s : %s', src, dst, msg));
                        end
                    else
                        % Plain string fallback
                        app.appendLog(sprintf('[RX] %s', char(result)));
                    end
                end
            catch ex
                app.appendLog(sprintf('[RX ERROR] %s', ex.message));
            end
        end

        % ── HELPERS ──────────────────────────────────────────────────
        function appendLog(app, text)
            ts  = datestr(now, 'HH:MM:SS'); %#ok<TNOW1,DATST>
            line = sprintf('[%s] %s', ts, text);
            current = app.LogArea.Value;
            if isempty(current) || (numel(current)==1 && isempty(current{1}))
                app.LogArea.Value = {line};
            else
                app.LogArea.Value = [current; {line}];
            end
            % Scroll to bottom
            scroll(app.LogArea, 'bottom');
        end

        function clearLog(app)
            app.LogArea.Value = {'[Log cleared]'};
        end

        function setStatus(app, text, color)
            switch text
                case 'TRANSMITTING'
                    icon = '▲';
                case 'LISTENING'
                    icon = '◉';
                otherwise
                    icon = '●';
            end
            app.StatusLabel.Text      = sprintf('%s %s', icon, text);
            app.StatusLabel.FontColor = color;
        end

        function stopTimer(app)
            if ~isempty(app.RxTimer) && isvalid(app.RxTimer)
                stop(app.RxTimer);
                delete(app.RxTimer);
            end
            app.RxTimer = [];
        end

        function val = safeField(~, s, field, default)
            if isfield(s, field)
                val = s.(field);
            else
                val = default;
            end
        end
    end

    % ================================================================
    %  App lifecycle (called by AppBase)
    % ================================================================
    methods (Access = public)

        function app = SDRRadioApp
            createComponents(app);
            registerApp(app, app.UIFigure);
            % Clean up timer when figure is closed
            app.UIFigure.CloseRequestFcn = @(~,~) app.delete();
            if nargout == 0
                clear app
            end
        end

        function delete(app)
            app.stopTimer();
            delete(app.UIFigure);
        end
    end
end