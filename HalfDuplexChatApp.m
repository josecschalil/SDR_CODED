classdef HalfDuplexChatApp < matlab.apps.AppBase
    % Half-duplex SDR chat UI that wraps the existing AX.25/AFSK chain
    % without modifying any current project files.

    properties (Access = public)
        UIFigure                    matlab.ui.Figure
        Grid                        matlab.ui.container.GridLayout

        HeaderPanel                 matlab.ui.container.Panel
        TitleLabel                  matlab.ui.control.Label
        SubtitleLabel               matlab.ui.control.Label
        StatusLamp                  matlab.ui.control.Lamp
        StatusLabel                 matlab.ui.control.Label
        ModeValueLabel              matlab.ui.control.Label
        DeviceValueLabel            matlab.ui.control.Label

        LeftPanel                   matlab.ui.container.Panel
        LeftGrid                    matlab.ui.container.GridLayout
        SourceField                 matlab.ui.control.EditField
        DestinationField            matlab.ui.control.EditField
        GainSlider                  matlab.ui.control.Slider
        GainValueLabel              matlab.ui.control.Label
        DeviceDropDown              matlab.ui.control.DropDown
        RefreshButton               matlab.ui.control.Button
        ListenButton                matlab.ui.control.Button
        RequestTxButton             matlab.ui.control.Button

        ComposePanel                matlab.ui.container.Panel
        ComposeGrid                 matlab.ui.container.GridLayout
        MessageArea                 matlab.ui.control.TextArea
        SendButton                  matlab.ui.control.Button
        ClearDraftButton            matlab.ui.control.Button
        HintLabel                   matlab.ui.control.Label

        LogPanel                    matlab.ui.container.Panel
        LogGrid                     matlab.ui.container.GridLayout
        SentArea                    matlab.ui.control.TextArea
        ReceivedArea                matlab.ui.control.TextArea
        ClearLogsButton             matlab.ui.control.Button
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
            cfg.rxPollPeriod = 2.5;
            cfg.framesPerPoll = 3;
            cfg.txPadSeconds = 2.0;
        end

        function createComponents(app)
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Name = 'Half-Duplex SDR Chat';
            app.UIFigure.Position = [80 60 1320 760];
            app.UIFigure.Color = [0.94 0.95 0.97];

            app.Grid = uigridlayout(app.UIFigure, [2 3]);
            app.Grid.RowHeight = {92, '1x'};
            app.Grid.ColumnWidth = {320, 420, '1x'};
            app.Grid.Padding = [18 18 18 18];
            app.Grid.RowSpacing = 16;
            app.Grid.ColumnSpacing = 16;

            app.HeaderPanel = uipanel(app.Grid);
            app.HeaderPanel.Layout.Row = 1;
            app.HeaderPanel.Layout.Column = [1 3];
            app.HeaderPanel.BackgroundColor = [0.09 0.15 0.22];
            app.HeaderPanel.BorderType = 'none';

            headerGrid = uigridlayout(app.HeaderPanel, [2 4]);
            headerGrid.RowHeight = {30, 26};
            headerGrid.ColumnWidth = {'1x', 26, 170, 240};
            headerGrid.Padding = [18 14 18 10];
            headerGrid.BackgroundColor = app.HeaderPanel.BackgroundColor;

            app.TitleLabel = uilabel(headerGrid);
            app.TitleLabel.Layout.Row = 1;
            app.TitleLabel.Layout.Column = 1;
            app.TitleLabel.Text = 'SDR AX.25 HALF-DUPLEX CHAT';
            app.TitleLabel.FontSize = 22;
            app.TitleLabel.FontWeight = 'bold';
            app.TitleLabel.FontColor = [0.97 0.98 0.99];

            app.SubtitleLabel = uilabel(headerGrid);
            app.SubtitleLabel.Layout.Row = 2;
            app.SubtitleLabel.Layout.Column = 1;
            app.SubtitleLabel.Text = 'Request TX before every transmission. The receiver resumes automatically after send.';
            app.SubtitleLabel.FontSize = 12;
            app.SubtitleLabel.FontColor = [0.80 0.86 0.92];

            app.StatusLamp = uilamp(headerGrid);
            app.StatusLamp.Layout.Row = 1;
            app.StatusLamp.Layout.Column = 2;
            app.StatusLamp.Color = [0.98 0.60 0.45];

            app.StatusLabel = uilabel(headerGrid);
            app.StatusLabel.Layout.Row = 1;
            app.StatusLabel.Layout.Column = 3;
            app.StatusLabel.Text = 'DISCONNECTED';
            app.StatusLabel.FontSize = 15;
            app.StatusLabel.FontWeight = 'bold';
            app.StatusLabel.FontColor = [0.98 0.60 0.45];

            app.ModeValueLabel = uilabel(headerGrid);
            app.ModeValueLabel.Layout.Row = 2;
            app.ModeValueLabel.Layout.Column = 3;
            app.ModeValueLabel.Text = 'Mode: DISCONNECTED';
            app.ModeValueLabel.FontSize = 12;
            app.ModeValueLabel.FontColor = [0.82 0.87 0.92];

            app.DeviceValueLabel = uilabel(headerGrid);
            app.DeviceValueLabel.Layout.Row = [1 2];
            app.DeviceValueLabel.Layout.Column = 4;
            app.DeviceValueLabel.Text = 'Device: none';
            app.DeviceValueLabel.HorizontalAlignment = 'right';
            app.DeviceValueLabel.FontSize = 12;
            app.DeviceValueLabel.FontColor = [0.82 0.87 0.92];

            app.LeftPanel = uipanel(app.Grid);
            app.LeftPanel.Layout.Row = 2;
            app.LeftPanel.Layout.Column = 1;
            app.LeftPanel.Title = 'Radio Control';
            app.LeftPanel.FontWeight = 'bold';
            app.LeftPanel.BackgroundColor = [1 1 1];

            app.LeftGrid = uigridlayout(app.LeftPanel, [13 2]);
            app.LeftGrid.RowHeight = {22, 30, 22, 30, 22, 46, 22, 30, 30, 38, 38, '1x', 24};
            app.LeftGrid.ColumnWidth = {'1x', 70};
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
            app.GainSlider.Value = -10;
            app.GainSlider.MajorTicks = [-50 -40 -30 -20 -10 0];
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
            app.RequestTxButton.BackgroundColor = [0.98 0.92 0.77];
            app.RequestTxButton.Enable = 'off';
            app.RequestTxButton.ButtonPushedFcn = @(~, ~) app.onRequestTx();

            radioNote = uitextarea(app.LeftGrid);
            radioNote.Layout.Row = 11;
            radioNote.Layout.Column = [1 2];
            radioNote.Editable = 'off';
            radioNote.Value = {'Half-duplex flow'; '1. Start Listening'; '2. Request TX'; '3. Send message'; '4. Receiver restarts'};
            radioNote.BackgroundColor = [0.97 0.98 1.00];

            spacer = uilabel(app.LeftGrid);
            spacer.Layout.Row = 12;
            spacer.Layout.Column = [1 2];
            spacer.Text = '';

            footer = uilabel(app.LeftGrid);
            footer.Layout.Row = 13;
            footer.Layout.Column = [1 2];
            footer.Text = sprintf('Center frequency: %.3f MHz', app.Config.centerFrequency / 1e6);
            footer.FontColor = [0.43 0.47 0.52];

            app.ComposePanel = uipanel(app.Grid);
            app.ComposePanel.Layout.Row = 2;
            app.ComposePanel.Layout.Column = 2;
            app.ComposePanel.Title = 'Compose Message';
            app.ComposePanel.FontWeight = 'bold';
            app.ComposePanel.BackgroundColor = [1 1 1];

            app.ComposeGrid = uigridlayout(app.ComposePanel, [6 1]);
            app.ComposeGrid.RowHeight = {24, '1x', 38, 38, 52, 24};
            app.ComposeGrid.Padding = [14 14 14 14];

            composeTitle = uilabel(app.ComposeGrid);
            composeTitle.Layout.Row = 1;
            composeTitle.Text = 'MESSAGE TEXT';
            composeTitle.FontWeight = 'bold';

            app.MessageArea = uitextarea(app.ComposeGrid);
            app.MessageArea.Layout.Row = 2;
            app.MessageArea.Value = {'Type your packet message here.'};
            app.MessageArea.FontSize = 13;

            app.SendButton = uibutton(app.ComposeGrid, 'push');
            app.SendButton.Layout.Row = 3;
            app.SendButton.Text = 'Send Message';
            app.SendButton.FontWeight = 'bold';
            app.SendButton.BackgroundColor = [0.86 0.90 0.98];
            app.SendButton.Enable = 'off';
            app.SendButton.ButtonPushedFcn = @(~, ~) app.onSend();

            app.ClearDraftButton = uibutton(app.ComposeGrid, 'push');
            app.ClearDraftButton.Layout.Row = 4;
            app.ClearDraftButton.Text = 'Clear Draft';
            app.ClearDraftButton.ButtonPushedFcn = @(~, ~) app.clearDraft();

            app.HintLabel = uilabel(app.ComposeGrid);
            app.HintLabel.Layout.Row = 5;
            app.HintLabel.Text = 'The Send button is unlocked only after Request TX to keep the link half-duplex.';
            app.HintLabel.WordWrap = 'on';
            app.HintLabel.FontColor = [0.42 0.46 0.50];

            composeFooter = uilabel(app.ComposeGrid);
            composeFooter.Layout.Row = 6;
            composeFooter.Text = 'Existing signal-chain files are not modified by this UI.';
            composeFooter.FontColor = [0.42 0.46 0.50];

            app.LogPanel = uipanel(app.Grid);
            app.LogPanel.Layout.Row = 2;
            app.LogPanel.Layout.Column = 3;
            app.LogPanel.Title = 'Traffic';
            app.LogPanel.FontWeight = 'bold';
            app.LogPanel.BackgroundColor = [1 1 1];

            app.LogGrid = uigridlayout(app.LogPanel, [4 2]);
            app.LogGrid.RowHeight = {22, '1x', 22, 30};
            app.LogGrid.ColumnWidth = {'1x', '1x'};
            app.LogGrid.Padding = [14 14 14 14];

            sentLabel = uilabel(app.LogGrid);
            sentLabel.Layout.Row = 1;
            sentLabel.Layout.Column = 1;
            sentLabel.Text = 'SENT MESSAGES';
            sentLabel.FontWeight = 'bold';

            recvLabel = uilabel(app.LogGrid);
            recvLabel.Layout.Row = 1;
            recvLabel.Layout.Column = 2;
            recvLabel.Text = 'RECEIVED MESSAGES';
            recvLabel.FontWeight = 'bold';

            app.SentArea = uitextarea(app.LogGrid);
            app.SentArea.Layout.Row = 2;
            app.SentArea.Layout.Column = 1;
            app.SentArea.Editable = 'off';
            app.SentArea.Value = {'[No messages sent yet]'};
            app.SentArea.FontName = 'Courier New';

            app.ReceivedArea = uitextarea(app.LogGrid);
            app.ReceivedArea.Layout.Row = 2;
            app.ReceivedArea.Layout.Column = 2;
            app.ReceivedArea.Editable = 'off';
            app.ReceivedArea.Value = {'[No messages received yet]'};
            app.ReceivedArea.FontName = 'Courier New';

            summaryLabel = uilabel(app.LogGrid);
            summaryLabel.Layout.Row = 3;
            summaryLabel.Layout.Column = [1 2];
            summaryLabel.Text = 'Status panel shows the actual radio/session mode for the selected Pluto.';
            summaryLabel.FontColor = [0.42 0.46 0.50];

            app.ClearLogsButton = uibutton(app.LogGrid, 'push');
            app.ClearLogsButton.Layout.Row = 4;
            app.ClearLogsButton.Layout.Column = [1 2];
            app.ClearLogsButton.Text = 'Clear Sent / Received Logs';
            app.ClearLogsButton.ButtonPushedFcn = @(~, ~) app.clearLogs();

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
                app.ModeValueLabel.Text = sprintf('Mode: Found %d Pluto device entries. Select one and continue.', numel(app.Radios) - 1);
            else
                app.ModeValueLabel.Text = 'Mode: No explicit Pluto IDs found. Using the default Pluto target.';
            end
        end

        function updateDeviceSummary(app)
            app.DeviceValueLabel.Text = ['Device: ', app.DeviceDropDown.Value];
        end

        function onListenButton(app)
            if strcmp(app.Mode, 'LISTENING')
                app.stopListening();
                app.updateStatus('READY', 'Listening stopped. Request TX to transmit or start listening again.', [0.50 0.48 0.13], [0.96 0.86 0.33]);
                app.ListenButton.Text = 'Start Listening';
                app.ListenButton.BackgroundColor = [0.83 0.92 0.87];
                app.RequestTxButton.Enable = 'on';
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
                app.updateStatus('LISTENING', 'Receiver is polling the selected Pluto for incoming packets.', [0.08 0.40 0.24], [0.26 0.78 0.47]);
            catch ex
                app.stopListening();
                app.updateStatus('ERROR', ex.message, [0.70 0.10 0.10], [0.92 0.29 0.29]);
                app.appendReceived(sprintf('[ERROR] %s', ex.message));
            end
        end

        function onRequestTx(app)
            if strcmp(app.Mode, 'TX READY')
                app.setTxReady(false);
                app.appendSent('[STATE] TX request cancelled. Receiver can be started again.');
                return
            end

            if strcmp(app.Mode, 'TRANSMITTING')
                return
            end

            app.stopListening();
            app.ListenButton.Text = 'Start Listening';
            app.ListenButton.BackgroundColor = [0.83 0.92 0.87];
            app.setTxReady(true);
            app.appendSent('[STATE] TX request granted locally. Send the packet now.');
        end

        function setTxReady(app, isReady)
            if isReady
                app.Mode = 'TX READY';
                app.RequestTxButton.Text = 'Cancel TX Request';
                app.RequestTxButton.BackgroundColor = [0.95 0.76 0.34];
                app.SendButton.Enable = 'on';
                app.updateStatus('TX READY', 'Half-duplex transmit window opened. Press Send to key the radio.', [0.55 0.34 0.00], [0.95 0.76 0.34]);
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
                uialert(app.UIFigure, 'Request TX before sending so the app stays in half-duplex mode.', 'TX Not Armed');
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
            app.updateStatus('TRANSMITTING', 'Packet modulation and Pluto transmission are in progress.', [0.54 0.21 0.00], [0.99 0.63 0.16]);
            drawnow;

            try
                [iq, txDuration] = plutoBuildPacketIQ(src, dst, msg, app.Config);
                tx = app.createTransmitter();
                transmitRepeat(tx, iq);
                pause(txDuration + 0.25);
                release(tx);

                app.appendSent(sprintf('[TX][%s -> %s][gain %.0f dB] %s', src, dst, app.GainSlider.Value, msg));
                app.MessageArea.Value = {''};
                app.LastPacketKey = string(src) + "|" + string(dst) + "|" + string(msg);
                app.LastPacketClock = tic;
            catch ex
                app.appendSent(sprintf('[TX ERROR] %s', ex.message));
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
                app.updateStatus('LISTENING', 'Transmit complete. Receiver resumed on the selected Pluto.', [0.08 0.40 0.24], [0.26 0.78 0.47]);
            catch ex
                app.Mode = 'READY';
                app.ListenButton.Text = 'Start Listening';
                app.ListenButton.BackgroundColor = [0.83 0.92 0.87];
                app.updateStatus('READY', ['Transmit complete, but RX restart failed: ', ex.message], [0.50 0.48 0.13], [0.96 0.86 0.33]);
                app.appendReceived(sprintf('[RX ERROR] %s', ex.message));
            end
        end

        function clearDraft(app)
            app.MessageArea.Value = {''};
        end

        function clearLogs(app)
            app.SentArea.Value = {'[Sent log cleared]'};
            app.ReceivedArea.Value = {'[Received log cleared]'};
        end

        function appendSent(app, line)
            app.SentArea.Value = app.appendLine(app.SentArea.Value, line);
            scroll(app.SentArea, 'bottom');
        end

        function appendReceived(app, line)
            app.ReceivedArea.Value = app.appendLine(app.ReceivedArea.Value, line);
            scroll(app.ReceivedArea, 'bottom');
        end

        function lines = appendLine(~, current, line)
            stamped = sprintf('[%s] %s', datestr(now, 'HH:MM:SS'), line); %#ok<TNOW1,DATST>
            if isempty(current) || (numel(current) == 1 && strcmp(current{1}, ''))
                lines = {stamped};
            elseif contains(current{1}, '[No messages') || contains(current{1}, '[Sent log') || contains(current{1}, '[Received log')
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
            app.ModeValueLabel.Text = ['Mode: ', detailText];
        end

        function openReceiver(app)
            app.closeReceiver();
            app.Rx = sdrrx('Pluto');
            app.applyRadioSelection(app.Rx);
            app.Rx.CenterFrequency = app.Config.centerFrequency;
            app.Rx.BasebandSampleRate = app.Config.fs_sdr;
            app.Rx.SamplesPerFrame = app.Config.fs_sdr;
            app.Rx.OutputDataType = 'double';
            app.Rx.GainSource = 'Manual';
            app.Rx.Gain = app.Config.rxGain;
        end

        function tx = createTransmitter(app)
            tx = sdrtx('Pluto');
            app.applyRadioSelection(tx);
            tx.CenterFrequency = app.Config.centerFrequency;
            tx.BasebandSampleRate = app.Config.fs_sdr;
            tx.Gain = round(app.GainSlider.Value);
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
                if powerLevel < app.Config.powerThreshold
                    return
                end

                audio = app.fmDemodulate(data);
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
                app.appendReceived(sprintf('[RX][%s -> %s][power %.2f] %s', src, dst, powerLevel, msg));
            catch ex
                app.appendReceived(sprintf('[RX ERROR] %s', ex.message));
                app.stopListening();
                app.ListenButton.Text = 'Start Listening';
                app.ListenButton.BackgroundColor = [0.83 0.92 0.87];
                app.RequestTxButton.Enable = 'on';
                app.updateStatus('READY', 'Receiver stopped after an RX error. Check Pluto connection and restart listening.', [0.50 0.48 0.13], [0.96 0.86 0.33]);
            end
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
