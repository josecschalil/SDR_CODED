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

            app.LeftGrid = uigridlayout(app.LeftPanel, [14 2]);
            app.LeftGrid.RowHeight = {22, 30, 22, 30, 22, 44, 22, 30, 30, 38, 38, 22, '1x', 24};
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

            logLabel = uilabel(app.LeftGrid);
            logLabel.Layout.Row = 11;
            logLabel.Layout.Column = [1 2];
            logLabel.Text = 'SCRIPT-STYLE SESSION LOG';
            logLabel.FontWeight = 'bold';

            helperLabel = uilabel(app.LeftGrid);
            helperLabel.Layout.Row = 12;
            helperLabel.Layout.Column = [1 2];
            helperLabel.Text = 'Left pane mirrors transmit.m / receive.m console flow.';
            helperLabel.FontColor = [0.43 0.47 0.52];

            app.ConsoleArea = uitextarea(app.LeftGrid);
            app.ConsoleArea.Layout.Row = 13;
            app.ConsoleArea.Layout.Column = [1 2];
            app.ConsoleArea.Editable = 'off';
            app.ConsoleArea.FontName = 'Courier New';
            app.ConsoleArea.Value = {'[Session log ready]'};

            footer = uilabel(app.LeftGrid);
            footer.Layout.Row = 14;
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
        end

        function onListenButton(app)
            if strcmp(app.Mode, 'LISTENING')
                app.stopListening();
                app.ListenButton.Text = 'Start Listening';
                app.ListenButton.BackgroundColor = [0.83 0.92 0.87];
                app.RequestTxButton.Enable = 'on';
                app.updateStatus('READY', 'Listening stopped.', [0.50 0.48 0.13], [0.96 0.86 0.33]);
                app.logConsole('Listening stopped.');
                return
            end

            if strcmp(app.Mode, 'TX READY')
                app.setTxReady(false);
            end

            try
                app.openReceiver();
                app.startRxTimer();
                app.ListenButton.Text = 'Stop Listening';
                app.ListenButton.BackgroundColor = [0.93 0.84 0.84];
                app.RequestTxButton.Enable = 'on';
                app.SendButton.Enable = 'off';
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
            if strcmp(app.Mode, 'TX READY')
                app.setTxReady(false);
                app.logConsole('TX request cancelled.');
                return
            end

            if strcmp(app.Mode, 'TRANSMITTING')
                return
            end

            app.stopListening();
            app.ListenButton.Text = 'Start Listening';
            app.ListenButton.BackgroundColor = [0.83 0.92 0.87];
            app.setTxReady(true);
            app.logConsole('TX request granted. Ready to transmit.');
        end

        function setTxReady(app, isReady)
            if isReady
                app.Mode = 'TX READY';
                app.RequestTxButton.Text = 'Cancel TX Request';
                app.RequestTxButton.BackgroundColor = [0.95 0.76 0.34];
                app.SendButton.Enable = 'on';
                app.updateStatus('TX READY', 'Half-duplex TX window opened.', [0.55 0.34 0.00], [0.95 0.76 0.34]);
            else
                app.Mode = 'READY';
                app.RequestTxButton.Text = 'Request TX';
                app.RequestTxButton.BackgroundColor = [0.98 0.92 0.77];
                app.SendButton.Enable = 'off';
                app.updateStatus('READY', 'Radio idle. Start listening or request TX.', [0.50 0.48 0.13], [0.96 0.86 0.33]);
            end
        end

        function onSend(app)
            src = upper(strtrim(app.SourceField.Value));
            dst = upper(strtrim(app.DestinationField.Value));
            msg = strtrim(strjoin(app.MessageArea.Value, newline));

            if ~strcmp(app.Mode, 'TX READY')
                uialert(app.UIFigure, 'Request TX before sending.', 'TX Not Armed');
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
            app.RequestTxButton.Text = 'Request TX';
            app.RequestTxButton.BackgroundColor = [0.98 0.92 0.77];
            app.SendButton.Enable = 'off';

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
            rx = sdrrx('Pluto');
            app.applyRadioSelection(rx);
            rx.CenterFrequency = app.Config.centerFrequency;
            rx.BasebandSampleRate = app.Config.fs_sdr;
            rx.SamplesPerFrame = app.Config.fs_sdr;
            rx.OutputDataType = 'double';
            rx.GainSource = 'Manual';
            rx.Gain = gainValue;
        end

        function tx = createTransmitter(app)
            tx = sdrtx('Pluto');
            app.applyRadioSelection(tx);
            tx.CenterFrequency = app.Config.centerFrequency;
            tx.BasebandSampleRate = app.Config.fs_sdr;
            tx.Gain = round(app.GainSlider.Value);
        end

        function tx = createFixedGainTransmitter(app, gainValue)
            tx = sdrtx('Pluto');
            app.applyRadioSelection(tx);
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
