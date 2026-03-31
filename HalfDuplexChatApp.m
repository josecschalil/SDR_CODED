classdef HalfDuplexChatApp < matlab.apps.AppBase
    % UI wrapper for the existing AX.25 SDR chain with half-duplex behavior
    % aligned to transmit.m and receive.m.

    properties (Access = public)
        UIFigure            matlab.ui.Figure
        RootGrid            matlab.ui.container.GridLayout

        HeaderPanel         matlab.ui.container.Panel
        TitleLabel          matlab.ui.control.Label
        SubtitleLabel       matlab.ui.control.Label
        StatusLamp          matlab.ui.control.Lamp
        StatusLabel         matlab.ui.control.Label
        DetailLabel         matlab.ui.control.Label
        DeviceValueLabel    matlab.ui.control.Label

        LeftPanel           matlab.ui.container.Panel
        LeftGrid            matlab.ui.container.GridLayout
        SourceField         matlab.ui.control.EditField
        DestinationField    matlab.ui.control.EditField
        GainSlider          matlab.ui.control.Slider
        GainValueLabel      matlab.ui.control.Label
        DeviceDropDown      matlab.ui.control.DropDown
        RefreshButton       matlab.ui.control.Button
        ListenButton        matlab.ui.control.Button
        RequestTxButton     matlab.ui.control.Button
        ReleaseTxButton     matlab.ui.control.Button
        ConsoleArea         matlab.ui.control.TextArea

        ChatPanel           matlab.ui.container.Panel
        ChatGrid            matlab.ui.container.GridLayout
        ChatArea            matlab.ui.control.TextArea
        MessageArea         matlab.ui.control.TextArea
        ActionGrid          matlab.ui.container.GridLayout
        SendButton          matlab.ui.control.Button
        ClearDraftButton    matlab.ui.control.Button
        ClearChatButton     matlab.ui.control.Button
    end

    properties (Access = private)
        Mode char = 'DISCONNECTED'
        Radios struct = struct('Label', {}, 'RadioID', {})
        RxTimer timer = timer.empty
        Rx = []
        Config struct
        LastPacketKey string = ""
        LastPacketClock double = NaN
        SessionActive logical = false
        CurrentTxOwner string = ""
        PendingTxRequester string = ""
        SessionKey string = ""
    end

    methods (Access = public)
        function app = HalfDuplexChatApp()
            app.Config = app.defaultConfig();
            app.createComponents();
            registerApp(app, app.UIFigure);
            app.refreshRadios();
            app.updateStatus('DISCONNECTED', 'Pick a Pluto and start listening.', [0.70 0.26 0.18], [0.98 0.60 0.45]);
            app.UIFigure.CloseRequestFcn = @(~, ~) app.delete();

            if nargout == 0
                clear app
            end
        end

        function delete(app)
            app.stopListening();
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                delete(app.UIFigure);
            end
        end
    end

    methods (Access = private)
        function cfg = defaultConfig(~)
            cfg.fs = 48000;
            cfg.fs_sdr = 960000;
            cfg.freqDev = 5000;
            cfg.centerFrequency = 433e6;
            cfg.rxGain = 40;
            cfg.powerThreshold = 1.0;
            cfg.rxPollPeriod = 1.5;
            cfg.framesPerPoll = 3;
            cfg.txPadSeconds = 2.0;
            cfg.ackTimeout = 60;
            cfg.ackCall = 'N0ACK';
            cfg.rxAckPreviewLength = 8;
            cfg.agcTarget = 30;
            cfg.agcMin = 20;
            cfg.agcMax = 45;
            cfg.agcGainMin = 0;
            cfg.agcGainMax = 60;
            cfg.agcGainCurrent = 20;
            cfg.ctrlConnect = '__CTRL_CONNECT__';
            cfg.ctrlRequestTx = '__CTRL_REQ_TX__';
            cfg.ctrlGrantTx = '__CTRL_GRANT_TX__';
            cfg.ctrlReleaseTx = '__CTRL_RELEASE_TX__';
        end

        function createComponents(app)
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Name = 'Half-Duplex SDR Chat';
            app.UIFigure.Position = [80 60 1320 760];
            app.UIFigure.Color = [0.95 0.96 0.98];

            app.RootGrid = uigridlayout(app.UIFigure, [2 2]);
            app.RootGrid.RowHeight = {92, '1x'};
            app.RootGrid.ColumnWidth = {350, '1x'};
            app.RootGrid.Padding = [18 18 18 18];
            app.RootGrid.RowSpacing = 16;
            app.RootGrid.ColumnSpacing = 16;

            app.HeaderPanel = uipanel(app.RootGrid);
            app.HeaderPanel.Layout.Row = 1;
            app.HeaderPanel.Layout.Column = [1 2];
            app.HeaderPanel.BackgroundColor = [0.08 0.14 0.22];
            app.HeaderPanel.BorderType = 'none';

            headerGrid = uigridlayout(app.HeaderPanel, [2 4]);
            headerGrid.RowHeight = {30, 24};
            headerGrid.ColumnWidth = {'1x', 26, 180, 250};
            headerGrid.Padding = [18 14 18 10];
            headerGrid.BackgroundColor = app.HeaderPanel.BackgroundColor;

            app.TitleLabel = uilabel(headerGrid);
            app.TitleLabel.Layout.Row = 1;
            app.TitleLabel.Layout.Column = 1;
            app.TitleLabel.Text = 'SDR AX.25 CHAT TERMINAL';
            app.TitleLabel.FontSize = 22;
            app.TitleLabel.FontWeight = 'bold';
            app.TitleLabel.FontColor = [0.98 0.98 0.99];

            app.SubtitleLabel = uilabel(headerGrid);
            app.SubtitleLabel.Layout.Row = 2;
            app.SubtitleLabel.Layout.Column = 1;
            app.SubtitleLabel.Text = 'UI flow follows transmit.m for TX ACK wait and receive.m for RX auto-ACK.';
            app.SubtitleLabel.FontSize = 12;
            app.SubtitleLabel.FontColor = [0.82 0.87 0.92];

            app.StatusLamp = uilamp(headerGrid);
            app.StatusLamp.Layout.Row = 1;
            app.StatusLamp.Layout.Column = 2;

            app.StatusLabel = uilabel(headerGrid);
            app.StatusLabel.Layout.Row = 1;
            app.StatusLabel.Layout.Column = 3;
            app.StatusLabel.FontSize = 15;
            app.StatusLabel.FontWeight = 'bold';

            app.DetailLabel = uilabel(headerGrid);
            app.DetailLabel.Layout.Row = 2;
            app.DetailLabel.Layout.Column = 3;
            app.DetailLabel.FontSize = 12;
            app.DetailLabel.FontColor = [0.82 0.87 0.92];

            app.DeviceValueLabel = uilabel(headerGrid);
            app.DeviceValueLabel.Layout.Row = [1 2];
            app.DeviceValueLabel.Layout.Column = 4;
            app.DeviceValueLabel.Text = 'Device: none';
            app.DeviceValueLabel.HorizontalAlignment = 'right';
            app.DeviceValueLabel.FontSize = 12;
            app.DeviceValueLabel.FontColor = [0.82 0.87 0.92];

            app.LeftPanel = uipanel(app.RootGrid);
            app.LeftPanel.Layout.Row = 2;
            app.LeftPanel.Layout.Column = 1;
            app.LeftPanel.Title = 'Control And Session Log';
            app.LeftPanel.FontWeight = 'bold';
            app.LeftPanel.BackgroundColor = [1 1 1];

            app.LeftGrid = uigridlayout(app.LeftPanel, [15 2]);
            app.LeftGrid.RowHeight = {22, 30, 22, 30, 22, 44, 22, 30, 30, 38, 38, 22, 22, '1x', 24};
            app.LeftGrid.ColumnWidth = {'1x', 72};
            app.LeftGrid.Padding = [14 14 14 14];

            srcLabel = uilabel(app.LeftGrid);
            srcLabel.Layout.Row = 1;
            srcLabel.Layout.Column = [1 2];
            srcLabel.Text = 'SOURCE CALLSIGN';
            srcLabel.FontWeight = 'bold';

            app.SourceField = uieditfield(app.LeftGrid, 'text');
            app.SourceField.Layout.Row = 2;
            app.SourceField.Layout.Column = [1 2];
            app.SourceField.Value = 'N0CALL';

            dstLabel = uilabel(app.LeftGrid);
            dstLabel.Layout.Row = 3;
            dstLabel.Layout.Column = [1 2];
            dstLabel.Text = 'DESTINATION CALLSIGN';
            dstLabel.FontWeight = 'bold';

            app.DestinationField = uieditfield(app.LeftGrid, 'text');
            app.DestinationField.Layout.Row = 4;
            app.DestinationField.Layout.Column = [1 2];
            app.DestinationField.Value = 'APRS';

            gainLabel = uilabel(app.LeftGrid);
            gainLabel.Layout.Row = 5;
            gainLabel.Layout.Column = [1 2];
            gainLabel.Text = 'TRANSMITTER GAIN (dB)';
            gainLabel.FontWeight = 'bold';

            app.GainSlider = uislider(app.LeftGrid);
            app.GainSlider.Layout.Row = 6;
            app.GainSlider.Layout.Column = 1;
            app.GainSlider.Limits = [-50 0];
            app.GainSlider.MajorTicks = [-50 -40 -30 -20 -10 0];
            app.GainSlider.Value = -10;
            app.GainSlider.ValueChangedFcn = @(~, ~) app.updateGainValue();
            app.GainSlider.ValueChangingFcn = @(~, evt) app.updateGainValue(evt.Value);

            app.GainValueLabel = uilabel(app.LeftGrid);
            app.GainValueLabel.Layout.Row = 6;
            app.GainValueLabel.Layout.Column = 2;
            app.GainValueLabel.Text = '-10 dB';
            app.GainValueLabel.HorizontalAlignment = 'right';

            deviceLabel = uilabel(app.LeftGrid);
            deviceLabel.Layout.Row = 7;
            deviceLabel.Layout.Column = [1 2];
            deviceLabel.Text = 'ADALM-PLUTO DEVICE';
            deviceLabel.FontWeight = 'bold';

            app.DeviceDropDown = uidropdown(app.LeftGrid);
            app.DeviceDropDown.Layout.Row = 8;
            app.DeviceDropDown.Layout.Column = 1;
            app.DeviceDropDown.Items = {'Searching for Pluto radios...'};
            app.DeviceDropDown.ValueChangedFcn = @(~, ~) app.updateDeviceSummary();

            app.RefreshButton = uibutton(app.LeftGrid, 'push');
            app.RefreshButton.Layout.Row = 8;
            app.RefreshButton.Layout.Column = 2;
            app.RefreshButton.Text = 'Refresh';
            app.RefreshButton.ButtonPushedFcn = @(~, ~) app.refreshRadios();

            app.ListenButton = uibutton(app.LeftGrid, 'push');
            app.ListenButton.Layout.Row = 9;
            app.ListenButton.Layout.Column = [1 2];
            app.ListenButton.Text = 'Start Listening';
            app.ListenButton.FontWeight = 'bold';
            app.ListenButton.BackgroundColor = [0.83 0.92 0.87];
            app.ListenButton.ButtonPushedFcn = @(~, ~) app.onListenButton();

            app.RequestTxButton = uibutton(app.LeftGrid, 'push');
            app.RequestTxButton.Layout.Row = 10;
            app.RequestTxButton.Layout.Column = [1 2];
            app.RequestTxButton.Text = 'Request TX';
            app.RequestTxButton.FontWeight = 'bold';
            app.RequestTxButton.Enable = 'off';
            app.RequestTxButton.BackgroundColor = [0.98 0.92 0.77];
            app.RequestTxButton.ButtonPushedFcn = @(~, ~) app.onRequestTx();

            app.ReleaseTxButton = uibutton(app.LeftGrid, 'push');
            app.ReleaseTxButton.Layout.Row = 11;
            app.ReleaseTxButton.Layout.Column = [1 2];
            app.ReleaseTxButton.Text = 'Release TX Control';
            app.ReleaseTxButton.FontWeight = 'bold';
            app.ReleaseTxButton.Enable = 'off';
            app.ReleaseTxButton.BackgroundColor = [0.90 0.89 0.97];
            app.ReleaseTxButton.ButtonPushedFcn = @(~, ~) app.onReleaseTx();

            logLabel = uilabel(app.LeftGrid);
            logLabel.Layout.Row = 12;
            logLabel.Layout.Column = [1 2];
            logLabel.Text = 'SCRIPT-STYLE SESSION LOG';
            logLabel.FontWeight = 'bold';

            helperLabel = uilabel(app.LeftGrid);
            helperLabel.Layout.Row = 13;
            helperLabel.Layout.Column = [1 2];
            helperLabel.Text = 'Same TX/RX path plus control keywords for token handoff.';
            helperLabel.FontColor = [0.43 0.47 0.52];

            app.ConsoleArea = uitextarea(app.LeftGrid);
            app.ConsoleArea.Layout.Row = 14;
            app.ConsoleArea.Layout.Column = [1 2];
            app.ConsoleArea.Editable = 'off';
            app.ConsoleArea.FontName = 'Courier New';
            app.ConsoleArea.Value = {'[Session log ready]'};

            footer = uilabel(app.LeftGrid);
            footer.Layout.Row = 15;
            footer.Layout.Column = [1 2];
            footer.Text = sprintf('Center frequency: %.3f MHz', app.Config.centerFrequency / 1e6);
            footer.FontColor = [0.43 0.47 0.52];

            app.ChatPanel = uipanel(app.RootGrid);
            app.ChatPanel.Layout.Row = 2;
            app.ChatPanel.Layout.Column = 2;
            app.ChatPanel.Title = 'Conversation';
            app.ChatPanel.FontWeight = 'bold';
            app.ChatPanel.BackgroundColor = [1 1 1];

            app.ChatGrid = uigridlayout(app.ChatPanel, [5 1]);
            app.ChatGrid.RowHeight = {24, '1x', 70, 42, 28};
            app.ChatGrid.Padding = [14 14 14 14];

            chatLabel = uilabel(app.ChatGrid);
            chatLabel.Layout.Row = 1;
            chatLabel.Text = 'COMBINED CHAT STREAM';
            chatLabel.FontWeight = 'bold';

            app.ChatArea = uitextarea(app.ChatGrid);
            app.ChatArea.Layout.Row = 2;
            app.ChatArea.Editable = 'off';
            app.ChatArea.FontName = 'Courier New';
            app.ChatArea.Value = {'[No traffic yet]'};

            app.MessageArea = uitextarea(app.ChatGrid);
            app.MessageArea.Layout.Row = 3;
            app.MessageArea.FontSize = 13;
            app.MessageArea.Value = {''};

            app.ActionGrid = uigridlayout(app.ChatGrid, [1 3]);
            app.ActionGrid.Layout.Row = 4;
            app.ActionGrid.ColumnWidth = {'1x', '1x', '1x'};
            app.ActionGrid.Padding = [0 0 0 0];

            app.SendButton = uibutton(app.ActionGrid, 'push');
            app.SendButton.Layout.Row = 1;
            app.SendButton.Layout.Column = 1;
            app.SendButton.Text = 'Send Message';
            app.SendButton.FontWeight = 'bold';
            app.SendButton.Enable = 'off';
            app.SendButton.BackgroundColor = [0.86 0.90 0.98];
            app.SendButton.ButtonPushedFcn = @(~, ~) app.onSend();

            app.ClearDraftButton = uibutton(app.ActionGrid, 'push');
            app.ClearDraftButton.Layout.Row = 1;
            app.ClearDraftButton.Layout.Column = 2;
            app.ClearDraftButton.Text = 'Clear Draft';
            app.ClearDraftButton.ButtonPushedFcn = @(~, ~) app.clearDraft();

            app.ClearChatButton = uibutton(app.ActionGrid, 'push');
            app.ClearChatButton.Layout.Row = 1;
            app.ClearChatButton.Layout.Column = 3;
            app.ClearChatButton.Text = 'Clear Chat';
            app.ClearChatButton.ButtonPushedFcn = @(~, ~) app.clearChat();

            hintLabel = uilabel(app.ChatGrid);
            hintLabel.Layout.Row = 5;
            hintLabel.Text = 'Compose box is intentionally smaller and anchored at the bottom like a chat app.';
            hintLabel.FontColor = [0.43 0.47 0.52];

            app.UIFigure.Visible = 'on';
        end

        function updateGainValue(app, value)
            if nargin < 2
                value = app.GainSlider.Value;
            end
            app.GainValueLabel.Text = sprintf('%.0f dB', value);
        end

        function refreshRadios(app)
            app.Radios = plutoDiscoverRadios();
            items = {app.Radios.Label};
            app.DeviceDropDown.Items = items;
            if isempty(app.DeviceDropDown.Value) || ~any(strcmp(app.DeviceDropDown.Value, items))
                app.DeviceDropDown.Value = items{1};
            end
            app.updateDeviceSummary();

            if numel(app.Radios) > 1
                app.logConsole(sprintf('Refresh complete. Found %d Pluto device entries.', numel(app.Radios) - 1));
            else
                app.logConsole('Refresh complete. No explicit Pluto IDs found, using default Pluto target.');
            end
        end

        function updateDeviceSummary(app)
            app.DeviceValueLabel.Text = ['Device: ', app.DeviceDropDown.Value];
            app.logConsole(['Selected radio target: ', char(app.selectedRadioId())]);
        end

        function onListenButton(app)
            if strcmp(app.Mode, 'LISTENING')
                app.stopListening();
                app.ListenButton.Text = 'Start Listening';
                app.ListenButton.BackgroundColor = [0.83 0.92 0.87];
                app.RequestTxButton.Enable = 'on';
                app.ReleaseTxButton.Enable = 'off';
                app.updateStatus('READY', 'Listening stopped.', [0.50 0.48 0.13], [0.96 0.86 0.33]);
                app.logConsole('Listening stopped.');
                return
            end

            try
                app.initializeSession();
                app.openReceiver();
                app.startRxTimer();
                app.ListenButton.Text = 'Stop Listening';
                app.ListenButton.BackgroundColor = [0.93 0.84 0.84];
                app.RequestTxButton.Enable = 'on';
                app.refreshTokenUi();
                app.updateStatus('LISTENING', 'Receiver active and will ACK every decoded message.', [0.08 0.40 0.24], [0.26 0.78 0.47]);
                app.logConsole('==============================');
                app.logConsole(sprintf('RECEIVER ACTIVE - %s', upper(strtrim(app.SourceField.Value))));
                app.logConsole('Will ACK every decoded message');
                app.logConsole('==============================');
            catch ex
                app.stopListening();
                app.updateStatus('ERROR', ex.message, [0.70 0.10 0.10], [0.92 0.29 0.29]);
                app.logConsole(['RX ERROR: ', ex.message]);
            end
        end

        function onRequestTx(app)
            if ~app.ensureSessionReady()
                return
            end

            if strcmp(app.Mode, 'TRANSMITTING')
                return
            end

            if app.sourceHasTxControl()
                app.logConsole('This station already has TX control.');
                app.appendEmphasizedChat('You already hold TX control.');
                return
            end

            ctrlMessage = sprintf('%s:%s', app.Config.ctrlRequestTx, upper(strtrim(app.SourceField.Value)));
            app.performControlTransmit(ctrlMessage, 'TX request sent to remote station.');
            app.PendingTxRequester = upper(strtrim(app.SourceField.Value));
            app.appendEmphasizedChat(sprintf('TX REQUEST SENT by %s', upper(strtrim(app.SourceField.Value))));
        end

        function onReleaseTx(app)
            if ~app.ensureSessionReady()
                return
            end
            if ~app.sourceHasTxControl()
                app.logConsole('Cannot release TX because this station is not the current owner.');
                return
            end

            target = app.PendingTxRequester;
            if strlength(target) == 0
                target = string(upper(strtrim(app.DestinationField.Value)));
            end

            grantMessage = sprintf('%s:%s', app.Config.ctrlGrantTx, target);
            app.performControlTransmit(grantMessage, sprintf('Released TX control to %s.', target));
            app.CurrentTxOwner = target;
            app.PendingTxRequester = "";
            app.appendEmphasizedChat(sprintf('TX CONTROL RELEASED TO %s', target));
            app.refreshTokenUi();
        end

        function onSend(app)
            src = upper(strtrim(app.SourceField.Value));
            dst = upper(strtrim(app.DestinationField.Value));
            msg = strtrim(strjoin(app.MessageArea.Value, newline));

            if ~app.ensureSessionReady()
                return
            end
            if ~app.sourceHasTxControl()
                uialert(app.UIFigure, 'This station does not currently hold TX control. Use Request TX first.', 'TX Control Required');
                return
            end
            if isempty(src) || isempty(dst)
                uialert(app.UIFigure, 'Source and destination callsigns are required.', 'Missing Callsign');
                return
            end
            if isempty(msg)
                uialert(app.UIFigure, 'Message text cannot be empty.', 'Missing Message');
                return
            end

            app.Mode = 'TRANSMITTING';
            app.SendButton.Enable = 'off';
            app.RequestTxButton.Enable = 'off';
            app.ReleaseTxButton.Enable = 'off';
            app.stopListening();
            app.updateStatus('TRANSMITTING', 'Transmitting and waiting for ACK like transmit.m.', [0.54 0.21 0.00], [0.99 0.63 0.16]);
            drawnow;

            try
                ackResult = app.transmitAndWaitForAck(src, dst, msg);
                app.appendChat(sprintf('[TX][%s -> %s] %s', src, dst, msg));
                if ackResult.received
                    app.appendChat(sprintf('[ACK][%s] %s', ackResult.src, ackResult.message));
                end
                app.MessageArea.Value = {''};
            catch ex
                app.logConsole(['TX ERROR: ', ex.message]);
                app.appendChat(sprintf('[TX ERROR] %s', ex.message));
            end

            app.RequestTxButton.Enable = 'on';
            app.refreshTokenUi();

            try
                app.openReceiver();
                app.startRxTimer();
                app.ListenButton.Text = 'Stop Listening';
                app.ListenButton.BackgroundColor = [0.93 0.84 0.84];
                app.updateStatus('LISTENING', 'Transmit complete. Receiver resumed.', [0.08 0.40 0.24], [0.26 0.78 0.47]);
                app.logConsole('Receiver resumed after transmit.');
            catch ex
                app.Mode = 'READY';
                app.ListenButton.Text = 'Start Listening';
                app.ListenButton.BackgroundColor = [0.83 0.92 0.87];
                app.updateStatus('READY', 'Transmit complete, but RX restart failed.', [0.50 0.48 0.13], [0.96 0.86 0.33]);
                app.logConsole(['RX restart failed: ', ex.message]);
            end
        end

        function initializeSession(app)
            source = string(upper(strtrim(app.SourceField.Value)));
            destination = string(upper(strtrim(app.DestinationField.Value)));
            if strlength(source) == 0 || strlength(destination) == 0
                error('Source and destination callsigns are required to start a session.');
            end

            sessionKey = source + "|" + destination;
            if app.SessionActive && app.SessionKey == sessionKey
                app.refreshTokenUi();
                return
            end

            app.SessionActive = true;
            app.SessionKey = sessionKey;
            app.PendingTxRequester = "";
            app.CurrentTxOwner = app.determineInitialTxOwner(source, destination);
            app.appendEmphasizedChat(sprintf('SESSION CONNECTED: %s <-> %s', source, destination));
            app.appendEmphasizedChat(sprintf('INITIAL TX OWNER: %s', app.CurrentTxOwner));
            app.logConsole(sprintf('Session established between %s and %s', source, destination));
            app.logConsole(sprintf('Initial TX owner by callsign length rule: %s', app.CurrentTxOwner));
            app.refreshTokenUi();
        end

        function owner = determineInitialTxOwner(~, source, destination)
            if strlength(source) < strlength(destination)
                owner = source;
            elseif strlength(destination) < strlength(source)
                owner = destination;
            else
                pair = sort({char(source), char(destination)});
                owner = string(pair{1});
            end
        end

        function tf = ensureSessionReady(app)
            tf = true;
            if ~app.SessionActive
                uialert(app.UIFigure, 'Start Listening first so the session can be initialized.', 'Session Not Started');
                tf = false;
            end
        end

        function tf = sourceHasTxControl(app)
            tf = app.CurrentTxOwner == string(upper(strtrim(app.SourceField.Value)));
        end

        function refreshTokenUi(app)
            hasToken = app.sourceHasTxControl();
            if hasToken
                app.SendButton.Enable = 'on';
                app.ReleaseTxButton.Enable = 'on';
            else
                app.SendButton.Enable = 'off';
                app.ReleaseTxButton.Enable = 'off';
            end
            if hasToken
                app.RequestTxButton.Text = 'Request TX';
                app.updateStatus('TX CONTROL', sprintf('%s currently holds the token.', char(app.CurrentTxOwner)), [0.17 0.33 0.68], [0.30 0.48 0.96]);
            else
                app.RequestTxButton.Text = 'Request TX';
                app.updateStatus('LISTENING', sprintf('Waiting for TX control from %s.', char(app.CurrentTxOwner)), [0.08 0.40 0.24], [0.26 0.78 0.47]);
            end
        end

        function performControlTransmit(app, controlMessage, successLog)
            app.Mode = 'TRANSMITTING';
            app.RequestTxButton.Enable = 'off';
            app.ReleaseTxButton.Enable = 'off';
            app.SendButton.Enable = 'off';
            app.stopListening();
            app.updateStatus('TRANSMITTING', 'Sending control packet using the same radio path.', [0.54 0.21 0.00], [0.99 0.63 0.16]);
            drawnow;

            src = upper(strtrim(app.SourceField.Value));
            dst = upper(strtrim(app.DestinationField.Value));
            app.transmitAndWaitForAck(src, dst, controlMessage);
            app.logConsole(successLog);

            app.RequestTxButton.Enable = 'on';
            try
                app.openReceiver();
                app.startRxTimer();
                app.ListenButton.Text = 'Stop Listening';
                app.ListenButton.BackgroundColor = [0.93 0.84 0.84];
            catch ex
                app.logConsole(['RX restart failed after control packet: ', ex.message]);
            end
            app.refreshTokenUi();
        end

        function appendEmphasizedChat(app, line)
            app.appendChat(['*** ', line, ' ***']);
        end

        function clearDraft(app)
            app.MessageArea.Value = {''};
        end

        function clearChat(app)
            app.ChatArea.Value = {'[Chat cleared]'};
            app.ConsoleArea.Value = {'[Session log ready]'};
        end

        function appendChat(app, line)
            app.ChatArea.Value = app.appendLine(app.ChatArea.Value, line, {'[No traffic yet]', '[Chat cleared]'});
            scroll(app.ChatArea, 'bottom');
        end

        function logConsole(app, line)
            app.ConsoleArea.Value = app.appendLine(app.ConsoleArea.Value, line, {'[Session log ready]'});
            scroll(app.ConsoleArea, 'bottom');
        end

        function lines = appendLine(~, current, line, resetMarkers)
            stamped = sprintf('[%s] %s', datestr(now, 'HH:MM:SS'), line); %#ok<TNOW1,DATST>
            if isempty(current)
                lines = {stamped};
                return
            end
            if numel(current) == 1 && any(strcmp(current{1}, resetMarkers))
                lines = {stamped};
            else
                lines = [current; {stamped}];
            end
        end

        function updateStatus(app, titleText, detailText, labelColor, lampColor)
            app.Mode = char(titleText);
            app.StatusLabel.Text = titleText;
            app.StatusLabel.FontColor = labelColor;
            app.StatusLamp.Color = lampColor;
            app.DetailLabel.Text = detailText;
        end

        function result = transmitAndWaitForAck(app, src, dst, msg)
            cfg = app.Config;
            result = struct('received', false, 'src', '', 'message', '');

            [txSignal, txDuration] = plutoBuildPacketIQ(src, dst, msg, cfg);
            tx = app.createTransmitter();
            rx = app.createReceiver(cfg.rxGain);

            app.logConsole('==============================');
            app.logConsole(sprintf('TX: Sending "%s"', msg));
            app.logConsole(sprintf('Waiting for ACK (timeout %ds)', cfg.ackTimeout));
            app.logConsole('==============================');

            transmitRepeat(tx, txSignal);
            startClock = tic;

            while toc(startClock) < cfg.ackTimeout
                pause(0.2);

                data = [];
                for idx = 1:cfg.framesPerPoll
                    data = [data; double(rx())]; %#ok<AGROW>
                end
                powerLevel = mean(abs(data).^2);

                app.logConsole(sprintf('Listening for ACK - power: %.2f  elapsed: %.0fs', powerLevel, toc(startClock)));
                if powerLevel < cfg.powerThreshold
                    continue
                end

                audio = app.fmDemodulate(data);
                bits = afsk_demodulate(audio, cfg.fs);
                if isempty(bits)
                    continue
                end

                try
                    [ackSrc, ~, ackMsg] = ax25_decode(bits);
                    app.logConsole(sprintf('Received from %s: %s', ackSrc, ackMsg));
                    if strcmp(ackSrc, cfg.ackCall) && contains(ackMsg, 'ACK')
                        result.received = true;
                        result.src = ackSrc;
                        result.message = ackMsg;
                        app.logConsole('==============================');
                        app.logConsole(sprintf('ACK RECEIVED FROM %s', ackSrc));
                        app.logConsole(sprintf('MSG : %s', ackMsg));
                        app.logConsole(sprintf('TIME: %.1f sec', toc(startClock)));
                        app.logConsole('==============================');
                        break
                    end
                catch
                end
            end

            try
                release(tx);
            catch
            end
            try
                release(rx);
            catch
            end

            if result.received
                app.logConsole('TX complete - message acknowledged.');
            else
                app.logConsole(sprintf('TX timed out after %.0f seconds - no ACK received.', cfg.ackTimeout));
            end

            pause(max(txDuration, 0.1));
        end

        function openReceiver(app)
            app.closeReceiver();
            app.Rx = app.createReceiver(app.Config.agcGainCurrent);
        end

        function rx = createReceiver(app, gainValue)
            radioId = app.selectedRadioId();
            if isempty(radioId) || strcmp(radioId, "default")
                rx = sdrrx('Pluto');
            else
                rx = sdrrx('Pluto', 'RadioID', char(radioId));
            end
            rx.CenterFrequency = app.Config.centerFrequency;
            rx.BasebandSampleRate = app.Config.fs_sdr;
            rx.SamplesPerFrame = app.Config.fs_sdr;
            rx.OutputDataType = 'double';
            rx.GainSource = 'Manual';
            rx.Gain = gainValue;
        end

        function tx = createTransmitter(app)
            radioId = app.selectedRadioId();
            if isempty(radioId) || strcmp(radioId, "default")
                tx = sdrtx('Pluto');
            else
                tx = sdrtx('Pluto', 'RadioID', char(radioId));
            end
            tx.CenterFrequency = app.Config.centerFrequency;
            tx.BasebandSampleRate = app.Config.fs_sdr;
            tx.Gain = round(app.GainSlider.Value);
        end

        function tx = createFixedGainTransmitter(app, gainValue)
            radioId = app.selectedRadioId();
            if isempty(radioId) || strcmp(radioId, "default")
                tx = sdrtx('Pluto');
            else
                tx = sdrtx('Pluto', 'RadioID', char(radioId));
            end
            tx.CenterFrequency = app.Config.centerFrequency;
            tx.BasebandSampleRate = app.Config.fs_sdr;
            tx.Gain = round(gainValue);
        end

        function applyRadioSelection(app, radioObj)
            radioId = app.selectedRadioId();
            if isempty(radioId) || strcmp(radioId, "default")
                return
            end
            try
                radioObj.RadioID = char(radioId);
            catch
            end
        end

        function id = selectedRadioId(app)
            selectedLabel = string(app.DeviceDropDown.Value);
            labels = string({app.Radios.Label});
            idx = find(labels == selectedLabel, 1);
            if isempty(idx)
                id = "default";
            else
                id = string(app.Radios(idx).RadioID);
            end
        end

        function startRxTimer(app)
            app.stopRxTimer();
            app.RxTimer = timer( ...
                'ExecutionMode', 'fixedSpacing', ...
                'BusyMode', 'drop', ...
                'Period', app.Config.rxPollPeriod, ...
                'TimerFcn', @(~, ~) app.pollReceiver());
            start(app.RxTimer);
        end

        function pollReceiver(app)
            if isempty(app.Rx)
                return
            end

            try
                data = [];
                for idx = 1:app.Config.framesPerPoll
                    data = [data; double(app.Rx())]; %#ok<AGROW>
                end
                powerLevel = mean(abs(data).^2);

                gainUpdate = app.applyRxAgc(powerLevel);
                if gainUpdate.changed
                    app.logConsole(sprintf('Power: %.1f  AGC -> %d dB', powerLevel, app.Config.agcGainCurrent));
                    return
                end

                app.logConsole(sprintf('Power: %.2f  Gain: %d dB', powerLevel, app.Config.agcGainCurrent));
                if powerLevel < app.Config.powerThreshold
                    app.logConsole('(no signal)');
                    return
                end
                app.logConsole('(decoding)');

                audio = app.fmDemodulate(data);
                if max(abs(audio)) < 1e-4
                    app.logConsole('too quiet');
                    return
                end

                bits = afsk_demodulate(audio, app.Config.fs);
                if isempty(bits)
                    return
                end

                [src, dst, msg] = ax25_decode(bits);
                key = string(src) + "|" + string(dst) + "|" + string(msg);
                if app.isDuplicatePacket(key)
                    return
                end

                app.LastPacketKey = key;
                app.LastPacketClock = tic;
                app.logConsole('==============================');
                app.logConsole('MESSAGE RECEIVED');
                app.logConsole(sprintf('FROM : %s', src));
                app.logConsole(sprintf('TO   : %s', dst));
                app.logConsole(sprintf('MSG  : %s', msg));
                app.logConsole('==============================');
                if app.handleControlMessage(src, dst, msg)
                    app.sendAckForReceivedMessage(src, msg);
                    return
                end

                app.appendChat(sprintf('[RX][%s -> %s] %s', src, dst, msg));
                app.sendAckForReceivedMessage(src, msg);
            catch ex
                app.logConsole(['RX ERROR: ', ex.message]);
                app.stopListening();
                app.ListenButton.Text = 'Start Listening';
                app.ListenButton.BackgroundColor = [0.83 0.92 0.87];
                app.RequestTxButton.Enable = 'on';
                app.updateStatus('READY', 'Receiver stopped after an RX error.', [0.50 0.48 0.13], [0.96 0.86 0.33]);
            end
        end

        function handled = handleControlMessage(app, src, dst, msg)
            handled = false;
            if startsWith(msg, app.Config.ctrlRequestTx)
                requester = string(app.messagePayload(msg));
                app.PendingTxRequester = requester;
                app.appendEmphasizedChat(sprintf('TX REQUEST FROM %s', requester));
                app.logConsole(sprintf('Control request received from %s', requester));
                handled = true;
                app.refreshTokenUi();
                return
            end

            if startsWith(msg, app.Config.ctrlGrantTx)
                newOwner = string(app.messagePayload(msg));
                app.CurrentTxOwner = newOwner;
                app.PendingTxRequester = "";
                app.appendEmphasizedChat(sprintf('TX CONTROL GRANTED TO %s', newOwner));
                app.logConsole(sprintf('Control grant received. New TX owner: %s', newOwner));
                handled = true;
                app.refreshTokenUi();
                return
            end

            if startsWith(msg, app.Config.ctrlReleaseTx)
                newOwner = string(app.messagePayload(msg));
                app.CurrentTxOwner = newOwner;
                app.PendingTxRequester = "";
                app.appendEmphasizedChat(sprintf('TX CONTROL RELEASED TO %s', newOwner));
                app.logConsole(sprintf('Control release received. New TX owner: %s', newOwner));
                handled = true;
                app.refreshTokenUi();
                return
            end

            if startsWith(msg, app.Config.ctrlConnect)
                app.appendEmphasizedChat(sprintf('SESSION CONTROL: %s -> %s', src, dst));
                app.logConsole(sprintf('Connection control received from %s', src));
                handled = true;
            end
        end

        function payload = messagePayload(~, msg)
            parts = split(string(msg), ':');
            if numel(parts) >= 2
                payload = join(parts(2:end), ':');
                payload = char(payload);
            else
                payload = '';
            end
        end

        function result = applyRxAgc(app, powerLevel)
            result.changed = false;
            if powerLevel <= 1.0
                return
            end

            if powerLevel > app.Config.agcMax || powerLevel < app.Config.agcMin
                errordB = 10 * log10(app.Config.agcTarget / max(powerLevel, 0.01));
                gainStep = max(-5, min(5, round(errordB * 0.5)));
                gainNew = max(app.Config.agcGainMin, min(app.Config.agcGainMax, app.Config.agcGainCurrent + gainStep));
                if gainNew ~= app.Config.agcGainCurrent
                    app.Config.agcGainCurrent = gainNew;
                    app.Rx.Gain = gainNew;
                    result.changed = true;
                end
            end
        end

        function sendAckForReceivedMessage(app, src, msg)
            app.logConsole(sprintf('Sending ACK to %s...', src));
            previewLength = min(app.Config.rxAckPreviewLength, length(msg));
            ackText = sprintf('ACK:%s', msg(1:previewLength));
            [ackIQ, ~] = plutoBuildPacketIQ(app.Config.ackCall, src, ackText, app.Config);

            app.closeReceiver();
            pause(0.1);
            tx = app.createFixedGainTransmitter(-10);
            transmitRepeat(tx, ackIQ);
            pause(2.5);
            try
                release(tx);
            catch
            end
            pause(0.1);

            app.openReceiver();
            app.logConsole('ACK sent - resuming receive');
            app.appendChat(sprintf('[ACK][%s -> %s] %s', app.Config.ackCall, src, ackText));
        end

        function tf = isDuplicatePacket(app, key)
            tf = false;
            if strlength(app.LastPacketKey) == 0 || isnan(app.LastPacketClock)
                return
            end
            if key == app.LastPacketKey && toc(app.LastPacketClock) < 6
                tf = true;
            end
        end

        function audio = fmDemodulate(app, data)
            fm = angle(data(2:end) .* conj(data(1:end-1)));
            fm = [fm; fm(end)];
            fm = fm * (app.Config.fs_sdr / (2 * pi * app.Config.freqDev));

            lpf = designfilt('lowpassfir', ...
                'PassbandFrequency', 3000, ...
                'StopbandFrequency', 8000, ...
                'PassbandRipple', 0.5, ...
                'StopbandAttenuation', 40, ...
                'SampleRate', app.Config.fs_sdr);

            filtered = filter(lpf, fm);
            decimation = app.Config.fs_sdr / app.Config.fs;
            audio = filtered(1:decimation:end);
            audio = audio - mean(audio);
            peak = max(abs(audio));
            if peak > 0
                audio = audio / peak;
            end
        end

        function stopListening(app)
            app.stopRxTimer();
            app.closeReceiver();
            if strcmp(app.Mode, 'LISTENING')
                app.Mode = 'READY';
            end
        end

        function stopRxTimer(app)
            if ~isempty(app.RxTimer) && isvalid(app.RxTimer)
                stop(app.RxTimer);
                delete(app.RxTimer);
            end
            app.RxTimer = timer.empty;
        end

        function closeReceiver(app)
            if ~isempty(app.Rx)
                try
                    release(app.Rx);
                catch
                end
            end
            app.Rx = [];
        end
    end
end
