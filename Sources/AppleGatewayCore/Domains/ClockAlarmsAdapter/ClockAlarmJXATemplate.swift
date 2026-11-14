import Foundation

enum ClockAlarmJXATemplate {
  static let source = #"""
  function run(argv) {
    const input = JSON.parse(argv[0]);
    const systemEvents = Application('System Events');
    const clock = Application('Clock');
    const currentApplication = Application.currentApplication();
    currentApplication.includeStandardAdditions = true;

    function waitUntil(predicate, message) {
      for (let attempt = 0; attempt < 100; attempt += 1) {
        if (predicate()) {
          return;
        }
        delay(0.05);
      }
      throw new Error(message);
    }

    function safe(callback, fallback) {
      try {
        return callback();
      } catch (_) {
        return fallback;
      }
    }

    function role(element) {
      return safe(() => String(element.role()), '');
    }

    function subrole(element) {
      return safe(() => String(element.subrole()), '');
    }

    function identifier(element) {
      return safe(() => String(element.attributes.byName('AXIdentifier').value()), '');
    }

    function description(element) {
      return safe(() => String(element.description()), '');
    }

    function name(element) {
      return safe(() => String(element.name()), '');
    }

    function value(element) {
      return safe(() => Number(element.value()), 0);
    }

    function descendants(element) {
      const output = [];
      const visit = current => {
        const children = safe(() => current.uiElements(), []);
        children.forEach(child => {
          output.push(child);
          visit(child);
        });
      };
      visit(element);
      return output;
    }

    function processAndWindow() {
      clock.activate();
      waitUntil(
        () => systemEvents.processes.whose({ name: 'Clock' })().length > 0,
        'Clock process did not launch'
      );
      const process = systemEvents.processes.whose({ name: 'Clock' })()[0];
      process.frontmost = true;
      waitUntil(() => process.windows().length > 0, 'Clock window did not appear');
      return { process: process, window: process.windows()[0] };
    }

    const context = processAndWindow();

    function selectAlarmsTab() {
      const radios = context.window.radioButtons();
      const candidates = radios.length > 1 ? radios : context.window.entireContents().filter(
        element => role(element) === 'AXRadioButton'
      );
      if (candidates.length < 2) {
        throw new Error('Clock Alarms tab is unavailable');
      }
      if (value(candidates[1]) !== 1) {
        candidates[1].actions.byName('AXPress').perform();
      }
      waitUntil(
        () => context.window.entireContents().some(element => identifier(element) === 'AXMTAAlarmCollectionView')
          || context.window.entireContents().some(element => description(element) === 'No Alarms'),
        'Clock Alarms view did not load'
      );
    }

    function alarmRows() {
      return context.window.entireContents().filter(element => {
        return role(element) === 'AXButton' && identifier(element).startsWith('Alarm-');
      });
    }

    function rowWithIdentifier(rowIdentifier) {
      return alarmRows().find(row => identifier(row) === rowIdentifier) || null;
    }

    function basicAlarm(row) {
      const elements = descendants(row);
      const timeElement = elements.find(element => /^\d{1,2}:\d{2}$/.test(description(element)));
      const labelElement = elements.find(element => identifier(element) === 'AlarmNameLabel');
      const enableSwitch = elements.find(element => identifier(element) === 'AlarmEnableSwitch');
      if (!timeElement || !labelElement || !enableSwitch) {
        throw new Error('Clock alarm row has an unsupported accessibility structure');
      }
      return {
        id: identifier(row),
        label: description(labelElement),
        time: description(timeElement).padStart(5, '0'),
        isEnabled: value(enableSwitch) === 1,
        repeatDays: []
      };
    }

    function currentSheet() {
      waitUntil(() => context.window.sheets().length > 0, 'Clock alarm editor did not appear');
      return context.window.sheets()[0];
    }

    function editorControls() {
      const sheet = currentSheet();
      const elements = sheet.entireContents();
      return {
        sheet: sheet,
        time: elements.find(element => role(element) === 'AXDateTimeArea'),
        repeatToggles: elements.filter(element => subrole(element) === 'AXToggle'),
        label: elements.find(element => role(element) === 'AXTextField'),
        buttons: elements.filter(element => role(element) === 'AXButton')
      };
    }

    const weekdayByToggleIndex = [
      'SUNDAY', 'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY'
    ];

    function repeatDayCheckboxValues() {
      const command = '/usr/bin/osascript -e '
        + "'tell application \"System Events\" to tell process \"Clock\" "
        + 'to tell sheet 1 of window 1 to get value of checkboxes 1 thru 7' + "'";
      return currentApplication.doShellScript(command).split(',').map(item => Number(item.trim()));
    }

    function repeatDaysFromEditor(controls) {
      return repeatDayCheckboxValues().flatMap((checkboxValue, index) => {
        return checkboxValue === 1 ? [weekdayByToggleIndex[index]] : [];
      });
    }

    function clickEditorButton(controls, index) {
      if (controls.buttons.length <= index) {
        throw new Error('Clock alarm editor button is unavailable');
      }
      controls.buttons[index].click();
      waitUntil(() => context.window.sheets().length === 0, 'Clock alarm editor did not close');
    }

    function repeatDaysForRow(rowIdentifier) {
      const row = rowWithIdentifier(rowIdentifier);
      if (!row) {
        throw new Error('Clock alarm disappeared while reading repeat days');
      }
      row.actions.byName('AXPress').perform();
      const controls = editorControls();
      const days = repeatDaysFromEditor(controls);
      clickEditorButton(controls, 1);
      return days;
    }

    function completeAlarm(alarm) {
      alarm.repeatDays = repeatDaysForRow(alarm.id);
      return alarm;
    }

    function listAlarms() {
      return alarmRows().map(basicAlarm).map(completeAlarm);
    }

    function requireUniqueAlarm(label) {
      const matches = alarmRows().map(basicAlarm).filter(alarm => alarm.label === label);
      if (matches.length !== 1) {
        throw new Error(matches.length === 0 ? 'Clock alarm is missing' : 'Clock alarm label is ambiguous');
      }
      return matches[0];
    }

    function openAlarmEditor(alarm) {
      const row = rowWithIdentifier(alarm.id);
      if (!row) {
        throw new Error('Clock alarm disappeared before editing');
      }
      row.actions.byName('AXPress').perform();
      return editorControls();
    }

    function openCreateEditor() {
      const addButton = context.window.entireContents().find(element => role(element) === 'AXMenuButton');
      if (!addButton) {
        throw new Error('Clock Add Alarm control is unavailable');
      }
      addButton.click();
      return editorControls();
    }

    function setTime(control, time) {
      if (!control) {
        throw new Error('Clock alarm time control is unavailable');
      }
      const parts = time.split(':');
      control.attributes.byName('AXFocused').value = true;
      delay(0.05);
      systemEvents.keystroke(parts[0]);
      systemEvents.keyCode(48);
      systemEvents.keystroke(parts[1]);
    }

    function setRepeatDays(controls, wantedDays) {
      const wanted = {};
      wantedDays.forEach(day => { wanted[day] = true; });
      const currentValues = repeatDayCheckboxValues();
      weekdayByToggleIndex.forEach((day, index) => {
        const shouldBeOn = Boolean(wanted[weekdayByToggleIndex[index]]);
        if ((currentValues[index] === 1) !== shouldBeOn) {
          const checkboxIndex = index + 1;
          const command = '/usr/bin/osascript -e '
            + "'tell application \"System Events\" to tell process \"Clock\" "
            + 'to tell sheet 1 of window 1 to click checkbox ' + checkboxIndex + "'";
          currentApplication.doShellScript(command);
          delay(0.1);
        }
      });
      const expectedDays = weekdayByToggleIndex.filter(day => Boolean(wanted[day]));
      const actualDays = repeatDaysFromEditor(controls);
      if (JSON.stringify(actualDays) !== JSON.stringify(expectedDays)) {
        throw new Error(
          'Clock repeat-day update was not applied: expected '
            + JSON.stringify(expectedDays) + ', actual ' + JSON.stringify(actualDays)
        );
      }
    }

    function saveEditor(controls) {
      clickEditorButton(controls, 0);
    }

    function alarmAfterMutation(label) {
      return completeAlarm(requireUniqueAlarm(label));
    }

    selectAlarmsTab();

    switch (input.operation) {
    case 'list':
      return JSON.stringify({ alarms: listAlarms() });
    case 'create': {
      const controls = openCreateEditor();
      setTime(controls.time, input.time);
      if (input.label !== null && input.label !== undefined) {
        controls.label.value = input.label;
      }
      setRepeatDays(controls, input.repeatDays || []);
      saveEditor(controls);
      const label = input.label || 'Alarm';
      return JSON.stringify({ success: true, alarm: alarmAfterMutation(label) });
    }
    case 'toggle': {
      const alarm = requireUniqueAlarm(input.label);
      const row = rowWithIdentifier(alarm.id);
      const enableSwitch = descendants(row).find(element => identifier(element) === 'AlarmEnableSwitch');
      const target = input.enabled === null || input.enabled === undefined ? !alarm.isEnabled : input.enabled;
      if (alarm.isEnabled !== target) {
        enableSwitch.click();
      }
      waitUntil(
        () => safe(() => requireUniqueAlarm(input.label).isEnabled === target, false),
        'Clock alarm toggle was not applied'
      );
      const updated = completeAlarm(requireUniqueAlarm(input.label));
      return JSON.stringify({ success: true, alarm: updated });
    }
    case 'update': {
      const alarm = requireUniqueAlarm(input.label);
      const controls = openAlarmEditor(alarm);
      if (input.time !== null && input.time !== undefined) {
        setTime(controls.time, input.time);
      }
      if (input.newLabel !== null && input.newLabel !== undefined) {
        controls.label.value = input.newLabel;
      }
      if (input.repeatDays !== null && input.repeatDays !== undefined) {
        setRepeatDays(controls, input.repeatDays);
      }
      saveEditor(controls);
      const targetLabel = input.newLabel || input.label;
      let updated = alarmAfterMutation(targetLabel);
      const updatedRepeatDays = updated.repeatDays;
      if (updated.isEnabled !== alarm.isEnabled) {
        const updatedRow = rowWithIdentifier(updated.id);
        const enableSwitch = descendants(updatedRow).find(element => identifier(element) === 'AlarmEnableSwitch');
        enableSwitch.click();
        waitUntil(
          () => safe(() => requireUniqueAlarm(targetLabel).isEnabled === alarm.isEnabled, false),
          'Clock alarm enabled state was not restored after editing'
        );
        updated = requireUniqueAlarm(targetLabel);
        updated.repeatDays = updatedRepeatDays;
      }
      return JSON.stringify({ success: true, alarm: updated });
    }
    case 'delete': {
      const alarm = requireUniqueAlarm(input.label);
      const controls = openAlarmEditor(alarm);
      clickEditorButton(controls, 2);
      return JSON.stringify({ success: true });
    }
    default:
      throw new Error('Unsupported Clock automation operation');
    }
  }
  """#
}
