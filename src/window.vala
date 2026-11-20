/* window.vala
 *
 * Copyright 2025 v81d
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using Gee;
using GLib;

using DeviceManager;
using NumericToolkit;

/* Define the class `DeviceRow`, which inherits from `Gtk.ListBoxRow`.
 * Used as a constructor for a single row in the device list sidebar.
 */
private class DeviceRow : Gtk.ListBoxRow {
  public DeviceObject device { get; private set; }

  public DeviceRow (DeviceObject device) {
    this.device = device;

    Adw.ActionRow row = new Adw.ActionRow ();
    row.set_title (device.native_path);
    row.set_subtitle (device.object_path);

    string icon_name = "battery-level-";

    if (device.capacity != null && device.capacity >= 0 && device.capacity <= 100) {
      int level = (int) (device.capacity / 10);

      switch (level) {
      case 0:
        icon_name += "0-";
        break;
      case 1:
        icon_name += "10-";
        break;
      case 2:
        icon_name += "20-";
        break;
      case 3:
        icon_name += "30-";
        break;
      case 4:
        icon_name += "40-";
        break;
      case 5:
        icon_name += "50-";
        break;
      case 6:
        icon_name += "60-";
        break;
      case 7:
        icon_name += "70-";
        break;
      case 8:
        icon_name += "80-";
        break;
      case 9:
        icon_name += "90-";
        break;
      case 10:
        icon_name += "100-";
        break;
      }

      if (device.state == _("Fully charged"))// will be 100%
        icon_name += "charged-";
      else if (device.state == _("Charging"))
        icon_name += (level == 10) ? "charged-" : "charging-";
      else if (device.state == _("Pending charge"))icon_name += "plugged-in-";
    } else icon_name = "battery-missing-";

    icon_name += "symbolic";

    // Due to the deprecation of `row.icon_name` and `row.set_icon_name ()`, the icon should be prepended as a widget
    Gtk.Image icon = new Gtk.Image.from_icon_name (icon_name);
    icon.set_pixel_size (24);
    row.add_prefix (icon);

    this.set_child (row);
  }
}

/* This class inherits from `Gtk.Box`.
 * Used as a constructor for a single section in the device information view.
 */
public delegate void ToggleCallback (bool active);
public delegate void SpinCallback (double value);

private class DeviceInfoSection : Gtk.Box {
  public string title { get; private set; }
  private Gtk.ListBox list { private get; private set; }

  public DeviceInfoSection (string title, ArrayList<DeviceInfoSectionData.DeviceProperty> properties) {
    this.title = title;
    this.set_orientation (Gtk.Orientation.VERTICAL);
    this.set_spacing (12);

    Gtk.Label title_label = new Gtk.Label (title);
    title_label.set_halign (Gtk.Align.START);
    title_label.add_css_class ("title-2");
    this.append (title_label);

    this.list = new Gtk.ListBox ();
    this.list.set_selection_mode (Gtk.SelectionMode.NONE);
    this.list.set_hexpand (true);
    this.list.add_css_class ("boxed-list");
    this.append (this.list);

    this.update (properties);
  }

  public void update (ArrayList<DeviceInfoSectionData.DeviceProperty> properties) {
    Gtk.ListBoxRow? row;
    while ((row = this.list.get_row_at_index (0)) != null)
      this.list.remove (row);

    foreach (DeviceInfoSectionData.DeviceProperty property in properties) {
      if (property.is_toggle) {
        Adw.SwitchRow switch_row = new Adw.SwitchRow ();
        switch_row.set_title (property.name);
        switch_row.set_active (property.toggle_state);
        switch_row.notify["active"].connect ((s, p) => {
          if (property.toggle_callback != null) {
            property.toggle_callback (switch_row.active);
          }
        });
        this.list.append (switch_row);
      } else if (property.is_spin) {
        Adw.SpinRow spin_row = new Adw.SpinRow.with_range (property.spin_min, property.spin_max, property.spin_step);
        spin_row.set_title (property.name);
        spin_row.set_value (property.spin_value);
        spin_row.notify["value"].connect ((s, p) => {
          if (property.spin_callback != null) {
            property.spin_callback (spin_row.value);
          }
        });
        this.list.append (spin_row);
      } else {
        Adw.ActionRow action_row = new Adw.ActionRow ();
        action_row.set_title (property.name);
        action_row.set_subtitle (property.value);
        action_row.set_subtitle_selectable (true);
        action_row.set_css_classes ({ "property", "monospace" });
        this.list.append (action_row);
      }
    }
  }
}

private class DeviceInfoSectionData {
  public class DeviceProperty {
    public string name { get; set; }
    public string value { get; set; }
    public bool is_toggle { get; set; }
    public bool toggle_state { get; set; }
    public ToggleCallback? toggle_callback;

    public bool is_spin { get; set; }
    public double spin_min { get; set; }
    public double spin_max { get; set; }
    public double spin_step { get; set; }
    public double spin_value { get; set; }
    public SpinCallback? spin_callback;

    public DeviceProperty (string name, string value) {
      this.name = name;
      this.value = value;
      this.is_toggle = false;
      this.is_spin = false;
    }

    public DeviceProperty.with_toggle (string name, bool state, owned ToggleCallback callback) {
      this.name = name;
      this.value = "";
      this.is_toggle = true;
      this.is_spin = false;
      this.toggle_state = state;
      this.toggle_callback = (owned) callback;
    }

    public DeviceProperty.with_spin (string name, double min, double max, double step, double val, owned SpinCallback callback) {
      this.name = name;
      this.value = "";
      this.is_toggle = false;
      this.is_spin = true;
      this.spin_min = min;
      this.spin_max = max;
      this.spin_step = step;
      this.spin_value = val;
      this.spin_callback = (owned) callback;
    }
  }

  public string title { get; private set; }
  public ArrayList<DeviceProperty> properties { get; private set; }

  public DeviceInfoSectionData (string title) {
    this.title = title;
    this.properties = new ArrayList<DeviceProperty> ();
  }

  public void set (string name, string? val) {
    if (val != null)this.properties.add (new DeviceProperty (name, val));
  }

  public void set_toggle (string name, bool state, owned ToggleCallback callback) {
    this.properties.add (new DeviceProperty.with_toggle (name, state, (owned) callback));
  }

  public void set_spin (string name, double min, double max, double step, double val, owned SpinCallback callback) {
    this.properties.add (new DeviceProperty.with_spin (name, min, max, step, val, (owned) callback));
  }
}

[GtkTemplate (ui = "/io/github/v81d/Wattage/window.ui")]
public class Wattage.Window : Adw.ApplicationWindow {
  // Bind template children to variables
  [GtkChild] unowned Adw.ToastOverlay main_toast_overlay;
  [GtkChild] unowned Adw.Spinner sidebar_spinner;
  [GtkChild] unowned Adw.Spinner content_spinner;
  [GtkChild] unowned Adw.OverlaySplitView split_view;
  [GtkChild] unowned Gtk.ListBox device_list;
  [GtkChild] unowned Gtk.Box device_info_box;
  [GtkChild] unowned Adw.StatusPage device_list_empty_status;
  [GtkChild] unowned Adw.StatusPage device_info_empty_status;

  private SimpleAction device_history_action;

  private Gtk.Builder preferences_dialog_builder;
  private Settings settings;

  private DeviceProber device_prober;
  private int selected_device_index = 0;
  private ArrayList<DeviceInfoSection> device_info_sections = new ArrayList<DeviceInfoSection> ();

  // Preferences and user settings
  private bool trivial_devices;
  private bool auto_refresh;
  private uint auto_refresh_cooldown;
  private uint auto_refresh_source_id = 0;
  private string energy_unit;
  private string power_unit;
  private string voltage_unit;

  private uint load_device_list_generation = 0;
  private uint load_device_info_generation = 0;
  private HistoryDialog? history_dialog;

  public Window (Gtk.Application app) {
    Object (application: app);

    this.device_prober = new DeviceProber ();
    this.load_device_list ();

    // This is the handler for selecting a device in the sidebar
    this.device_list.row_selected.connect ((list, row) => {
      if (row is DeviceRow) {
        DeviceRow device_row = (DeviceRow) row;
        this.selected_device_index = device_row.get_index ();
        this.device_info_empty_status.set_visible (false);
        this.device_history_action.set_enabled (device_row.device.has_history);
        this.load_device_info (device_row.device);
      } else {
        this.device_history_action.set_enabled (false);
      }
    });

    this.initialize_gsettings ();
    this.initialize_preferences_dialog ();
  }

  construct {
    SimpleAction preferences_action = new SimpleAction ("preferences", null);
    preferences_action.activate.connect (this.on_preferences_action);
    this.add_action (preferences_action);

    SimpleAction refresh_action = new SimpleAction ("refresh", null);
    refresh_action.activate.connect (this.on_refresh_action);
    this.add_action (refresh_action);

    SimpleAction select_next_device_action = new SimpleAction ("select_next_device", null);
    select_next_device_action.activate.connect (this.on_select_next_device_action);
    this.add_action (select_next_device_action);

    SimpleAction select_previous_device_action = new SimpleAction ("select_previous_device", null);
    select_previous_device_action.activate.connect (this.on_select_previous_device_action);
    this.add_action (select_previous_device_action);

    this.device_history_action = new SimpleAction ("device_history", null);
    this.device_history_action.set_enabled (false);
    this.device_history_action.activate.connect (this.on_device_history_action);
    this.add_action (this.device_history_action);
  }

  private void start_auto_refresh () {
    if (!this.auto_refresh || this.auto_refresh_source_id != 0)return;

    this.auto_refresh_source_id = Timeout.add_seconds (this.auto_refresh_cooldown, () => {
      if (!this.auto_refresh) {
        this.auto_refresh_source_id = 0;
        return false;
      }

      this.load_device_list ();
      return true;
    });
  }

  private void stop_auto_refresh () {
    if (this.auto_refresh_source_id != 0) {
      Source.remove (this.auto_refresh_source_id);
      this.auto_refresh_source_id = 0;
    }
  }

  /* This is mostly used for dropdowns in the preferences menu.
   * The function will return the index of a value inside a given array.
   */
  private static int get_string_list_index (Gtk.StringList list, string val) {
    for (int i = 0; i < list.n_items; i++)
      if (list.get_string (i) == val)return i;

    return 0;
  }

  private void initialize_gsettings () {
    this.settings = new Settings ("io.github.v81d.Wattage");

    // Devices
    this.trivial_devices = this.settings.get_boolean ("trivial-devices");

    // Automation
    this.auto_refresh = this.settings.get_boolean ("auto-refresh");
    this.auto_refresh_cooldown = this.settings.get_uint ("auto-refresh-cooldown");

    // Measurements
    this.energy_unit = this.settings.get_string ("energy-unit");
    this.power_unit = this.settings.get_string ("power-unit");
    this.voltage_unit = this.settings.get_string ("voltage-unit");
  }

  private void initialize_preferences_dialog () {
    this.preferences_dialog_builder = new Gtk.Builder ();
    try {
      this.preferences_dialog_builder.add_from_resource ("/io/github/v81d/Wattage/preferences-dialog.ui");
    } catch (Error e) {
      stderr.printf ("Could not open preferences dialog: %s\n", e.message);
    }

    // Trivial devices switch
    Adw.SwitchRow trivial_devices_switch = this.preferences_dialog_builder.get_object ("trivial_devices_switch") as Adw.SwitchRow;
    trivial_devices_switch.set_active (this.trivial_devices);
    trivial_devices_switch.notify["active"].connect (() => {
      bool is_active = trivial_devices_switch.get_active ();
      this.settings.set_boolean ("trivial-devices", is_active);
      this.trivial_devices = is_active;
      load_device_list ();
    });

    // Auto-refresh switch
    Adw.SwitchRow auto_refresh_switch = this.preferences_dialog_builder.get_object ("auto_refresh_switch") as Adw.SwitchRow;
    auto_refresh_switch.set_active (this.auto_refresh);

    if (this.auto_refresh)this.start_auto_refresh ();

    auto_refresh_switch.notify["active"].connect (() => {
      bool is_active = auto_refresh_switch.get_active ();
      this.settings.set_boolean ("auto-refresh", is_active);
      this.auto_refresh = is_active;

      if (is_active)this.start_auto_refresh ();
      else this.stop_auto_refresh ();

      load_device_list ();
    });

    // Auto-refresh delay
    Adw.SpinRow auto_refresh_cooldown_row = this.preferences_dialog_builder.get_object ("auto_refresh_cooldown_row") as Adw.SpinRow;
    auto_refresh_cooldown_row.set_value (this.auto_refresh_cooldown);

    auto_refresh_cooldown_row.notify["value"].connect (() => {
      uint cooldown = (uint) auto_refresh_cooldown_row.get_value ();
      this.settings.set_uint ("auto-refresh-cooldown", cooldown);
      this.auto_refresh_cooldown = cooldown;

      // Restart auto-refresh loop
      if (this.auto_refresh) {
        this.stop_auto_refresh ();
        this.start_auto_refresh ();
      }

      load_device_list ();
    });

    // Energy unit
    Adw.ComboRow energy_unit_row = this.preferences_dialog_builder.get_object ("energy_unit") as Adw.ComboRow;
    Gtk.StringList energy_units = (Gtk.StringList) energy_unit_row.get_model ();
    energy_unit_row.set_selected (get_string_list_index (energy_units, this.energy_unit)); // tried to use `.find()` but the compiler keeps saying it doesn't exist for some reason :(
    energy_unit_row.notify["selected"].connect (() => {
      string selected_unit = energy_units.get_string (energy_unit_row.get_selected ());
      this.settings.set_string ("energy-unit", selected_unit);
      this.energy_unit = selected_unit;
      load_device_list ();
    });

    // Power unit
    Adw.ComboRow power_unit_row = this.preferences_dialog_builder.get_object ("power_unit") as Adw.ComboRow;
    Gtk.StringList power_units = (Gtk.StringList) power_unit_row.get_model ();
    power_unit_row.set_selected (get_string_list_index (power_units, this.power_unit));
    power_unit_row.notify["selected"].connect (() => {
      string selected_unit = power_units.get_string (power_unit_row.get_selected ());
      this.settings.set_string ("power-unit", selected_unit);
      this.power_unit = selected_unit;
      load_device_list ();
    });

    // Voltage unit
    Adw.ComboRow voltage_unit_row = this.preferences_dialog_builder.get_object ("voltage_unit") as Adw.ComboRow;
    Gtk.StringList voltage_units = (Gtk.StringList) voltage_unit_row.get_model ();
    voltage_unit_row.set_selected (get_string_list_index (voltage_units, this.voltage_unit));
    voltage_unit_row.notify["selected"].connect (() => {
      string selected_unit = voltage_units.get_string (voltage_unit_row.get_selected ());
      this.settings.set_string ("voltage-unit", selected_unit);
      this.voltage_unit = selected_unit;
      load_device_list ();
    });
  }

  private void on_preferences_action () {
    Adw.PreferencesDialog preferences_dialog = this.preferences_dialog_builder.get_object ("preferences_dialog") as Adw.PreferencesDialog;
    preferences_dialog.present (this);
  }

  private static void add_section_metric (DeviceInfoSectionData section,
                                          double? val,
                                          string label,
                                          string unit) {
    if (val != null) {
      double? converted = si_convert (val, unit);
      if (converted != null)
        section.set (label, "%.03f %s".printf (converted, unit));
    }
  }

  private void append_device (DeviceObject device) {
    DeviceRow row = new DeviceRow (device);
    this.device_list.append (row);
  }

  private void load_device_list () {
    uint generation = ++this.load_device_list_generation;

    this.sidebar_spinner.set_visible (true);

    Gtk.ListBoxRow? row;

    while ((row = this.device_list.get_row_at_index (0)) != null)
      this.device_list.remove (row);

    new Thread<void> ("load-device-list", () => {
      ArrayList<DeviceObject> devices;

      try {
        devices = this.device_prober.get_devices ();
        device_list_empty_status.set_visible (false);
        this.device_info_empty_status.set_visible (false);
      } catch (Error e) {
        stderr.printf ("Failed to load power devices: %s\n", e.message);
        devices = new ArrayList<DeviceObject> ();
      }

      Idle.add (() => {
        if (generation != this.load_device_list_generation)return false;

        foreach (DeviceObject device in devices) {
          this.history_dialog?.update_device (device);

          if (!this.trivial_devices && device.is_trivial ())continue;
          this.append_device (device);
        }

        if (this.device_list.get_row_at_index (this.selected_device_index) != null)
          this.device_list.select_row (this.device_list.get_row_at_index (this.selected_device_index));
        else if (this.device_list.get_row_at_index (0) != null) {
          stdout.printf ("The device at index %s can no longer be found. The first device will be selected as fallback.\n", this.selected_device_index.to_string ());
          this.device_list.select_row (this.device_list.get_row_at_index (0));
        } else {
          stderr.printf ("No power devices have been detected by UPower.\n");
          this.device_list_empty_status.set_visible (true);
          this.device_info_empty_status.set_visible (true);
          this.device_history_action.set_enabled (false);
        }

        this.sidebar_spinner.set_visible (false);

        return false;
      });
    });
  }

  private void load_device_info (DeviceObject device) {
    uint generation = ++this.load_device_info_generation;

    this.content_spinner.set_visible (true);

    new Thread<void> ("load-device-info", () => {
      ArrayList<DeviceInfoSectionData> sections = new ArrayList<DeviceInfoSectionData> ();

      DeviceInfoSectionData general_info = new DeviceInfoSectionData (_("General Information"));
      general_info.set (_("Native Path"), device.native_path);
      general_info.set (_("Object Path"), device.object_path);
      general_info.set (_("Device Type"), device.device_type);
      general_info.set (_("Has History"), device.has_history ? "Yes" : "No");
      sections.add (general_info);

      DeviceInfoSectionData model_details = new DeviceInfoSectionData (_("Model Details"));
      model_details.set (_("Vendor"), device.vendor);
      model_details.set (_("Serial Number"), device.serial);
      model_details.set (_("Model Name"), device.model);
      model_details.set (_("Technology"), device.technology);
      sections.add (model_details);

      DeviceInfoSectionData health_stats = new DeviceInfoSectionData (_("Health Evaluations"));

      if (device.capacity != null)
        health_stats.set (_("State of Health"), "%.03f%%".printf (device.capacity));

      if (device.health_description != null)
        health_stats.set (_("Device Condition"), device.health_description);

      sections.add (health_stats);

      DeviceInfoSectionData charging_status = new DeviceInfoSectionData (_("Charging Status"));

      if (device.charge_threshold_supported) {
        charging_status.set_toggle (_("Limit Battery Charge"), device.charge_threshold_enabled, (active) => {
          new Thread<void> ("toggle-charge-threshold", () => {
            try {
              device.upower_proxy.enable_charge_threshold (active);
              Idle.add (() => {
                this.load_device_list ();
                return false;
              });
            } catch (Error e) {
              stderr.printf ("Failed to toggle charge threshold: %s\n", e.message);
              Idle.add (() => {
                this.main_toast_overlay.add_toast (new Adw.Toast (_("Failed to toggle charge threshold")));
                return false;
              });
            }
          });
        });

        if (device.charge_threshold_enabled) {
          if (device.charge_start_threshold != null) {
            charging_status.set_spin (_("Charge Start Threshold"), 0, 95, 5, (double) device.charge_start_threshold, (val) => {
              uint32 uval = (uint32) val;
              write_sysfs_value (device.native_path, "charge_control_start_threshold", uval);
              write_sysfs_value (device.native_path, "charge_start_threshold", uval);
              device.charge_start_threshold = uval;
            });
          }

          if (device.charge_end_threshold != null) {
            charging_status.set_spin (_("Charge End Threshold"), 50, 100, 5, (double) device.charge_end_threshold, (val) => {
              uint32 uval = (uint32) val;
              write_sysfs_value (device.native_path, "charge_control_end_threshold", uval);
              write_sysfs_value (device.native_path, "charge_stop_threshold", uval);
              device.charge_end_threshold = uval;
            });
          }
        }
      }

      if (device.charge_cycles != null)
        charging_status.set (_("Cycle Count"), device.charge_cycles.to_string ());

      double? current_charge = calculate_percentage (device.energy, device.energy_full);
      if (current_charge != null)
        charging_status.set (_("Current Charge Percentage"), "%.03f%%".printf (current_charge));

      charging_status.set (_("State"), device.state);

      sections.add (charging_status);

      DeviceInfoSectionData time_calculations = new DeviceInfoSectionData (_("Time Calculations"));

      string? time_to_empty = seconds_to_hms (device.time_to_empty);
      if (time_to_empty != null)
        time_calculations.set (_("Time to Empty"), time_to_empty);

      string? time_to_full = seconds_to_hms (device.time_to_full);
      if (time_to_full != null)
        time_calculations.set (_("Time to Full"), time_to_full);

      if (
          device.energy_full != null &&
          device.energy_rate != null &&
          device.energy_rate > 0 &&
          device.state == _("Discharging")
      ) {
        string? projected_battery_life = seconds_to_hms ((int64) (device.energy_full / device.energy_rate * 3600));
        if (projected_battery_life != null)
          time_calculations.set (_("Projected Battery Life"), projected_battery_life);
      }

      if (
          device.energy_full != null &&
          device.energy_rate != null &&
          device.energy_rate > 0 &&
          device.state == _("Charging")
      ) {
        string? projected_charging_time = seconds_to_hms ((int64) (device.energy_full / device.energy_rate * 3600));
        if (projected_charging_time != null)
          time_calculations.set (_("Projected Charging Time"), projected_charging_time);
      }

      sections.add (time_calculations);

      DeviceInfoSectionData sensor_readings = new DeviceInfoSectionData (_("Sensor Readings"));

      if (device.temperature != null)
        sensor_readings.set (_("Temperature"), "%.03f°C".printf (device.temperature));

      sections.add (sensor_readings);

      DeviceInfoSectionData energy_metrics = new DeviceInfoSectionData (_("Energy Metrics"));

      Window.add_section_metric (energy_metrics, device.energy_full_design,
                                 _("Maximum Rated Capacity"), this.energy_unit);

      Window.add_section_metric (energy_metrics, device.energy_full,
                                 _("Maximum Capacity"), this.energy_unit);

      Window.add_section_metric (energy_metrics, device.energy,
                                 _("Remaining Energy"), this.energy_unit);

      Window.add_section_metric (energy_metrics, device.energy_rate,
                                 _("Net Energy Rate"), this.power_unit);

      sections.add (energy_metrics);

      DeviceInfoSectionData voltage_stats = new DeviceInfoSectionData (_("Voltage Statistics"));

      if (device.voltage_min_design != null) {
        double? converted = si_convert (device.voltage_min_design, this.voltage_unit);
        if (converted != null)
          voltage_stats.set (_("Minimum Rated Voltage"), "%.03f %s".printf (converted, this.voltage_unit));
      }

      if (device.voltage != null) {
        double? converted = si_convert (device.voltage, this.voltage_unit);
        if (converted != null)
          voltage_stats.set (_("Current Voltage"), "%.03f %s".printf (converted, this.voltage_unit));
      }

      sections.add (voltage_stats);

      Idle.add (() => {
        if (generation != this.load_device_info_generation)return false;

        ArrayList<string> existing_titles = new ArrayList<string> ();
        foreach (DeviceInfoSection section in this.device_info_sections)existing_titles.add (section.title);

        ArrayList<string> new_titles = new ArrayList<string> ();
        foreach (DeviceInfoSectionData section in sections)
          if (section.properties.size > 0)new_titles.add (section.title);

        // Check if both title arrays match
        bool titles_match = false;

        if (existing_titles.size == new_titles.size) {
          titles_match = true;
          for (int i = 0; i < existing_titles.size; i++) {
            if (existing_titles.get (i) != new_titles.get (i)) {
              titles_match = false;
              break;
            }
          }
        }

        /* We should reconstruct the entire content view if the two arrays do not match.
         * If we were to simply append the missing sections, they would be added directly
         * to the end of the content, which is not always desired. Rebuilding the view
         * would be the simplest way to resolve this. If the two arrays do match, however,
         * we should just update existing sections in place.
         */
        if (titles_match) {
          foreach (DeviceInfoSectionData section in sections) {
            if (section.properties.size == 0)continue;

            // Match existing sections by title
            DeviceInfoSection ? existing_section = null;
            foreach (DeviceInfoSection s in this.device_info_sections) {
              if (s.title == section.title) {
                existing_section = s;
                break;
              }
            }

            if (existing_section != null)existing_section.update (section.properties);
          }
        } else {
          foreach (DeviceInfoSection s in this.device_info_sections)this.device_info_box.remove (s);
          this.device_info_sections.clear ();

          foreach (DeviceInfoSectionData section in sections) {
            if (section.properties.size == 0)continue;

            DeviceInfoSection s = new DeviceInfoSection (section.title, section.properties);
            this.device_info_box.append (s);
            this.device_info_sections.add (s);
          }
        }

        this.content_spinner.set_visible (false);
        this.device_info_empty_status.set_visible (this.device_info_sections.size == 0);

        return false;
      });
    });
  }

  public void on_device_history_action () {
    var row = this.device_list.get_selected_row () as DeviceRow;
    if (row == null) {
      this.main_toast_overlay.add_toast (new Adw.Toast (_("No device is currently selected.")));
      return;
    }

    if (this.history_dialog == null) {
      this.history_dialog = new HistoryDialog (row.device, this.settings, this.power_unit);
      this.history_dialog.refresh_requested.connect (this.load_device_list);
      this.history_dialog.closed.connect (this.on_history_closed);
    }

    this.history_dialog.present (this);
  }

  private void on_history_closed () {
    var closing_dialog = this.history_dialog;
    Idle.add_once (() => {
      if (this.history_dialog == closing_dialog)
        this.history_dialog = null;
    });
  }

  [GtkCallback]
  public void on_toggle_sidebar_toggled (Gtk.ToggleButton button) {
    bool is_active = button.get_active ();
    this.split_view.set_show_sidebar (is_active);
  }

  // Keyboard shortcut select next device action
  private void on_select_next_device_action () {
    if (this.device_list.get_selected_row () != this.device_list.get_last_child ())
      this.device_list.select_row (this.device_list.get_row_at_index (this.selected_device_index + 1));
  }

  // Keyboard shortcut select previous device action
  private void on_select_previous_device_action () {
    if (this.device_list.get_selected_row () != this.device_list.get_first_child ())
      this.device_list.select_row (this.device_list.get_row_at_index (this.selected_device_index - 1));
  }

  // Keyboard shortcut refresh action
  private void on_refresh_action () {
    load_device_list ();
  }

  // Refresh button clicked action
  [GtkCallback]
  public void on_refresh_clicked (Gtk.Button _) {
    load_device_list ();
  }

  private static void write_sysfs_value (string battery_name, string file_name, uint32 value) {
    string path = "/sys/class/power_supply/%s/%s".printf (battery_name, file_name);
    if (FileUtils.test (path, FileTest.EXISTS)) {
      FileStream? stream = FileStream.open (path, "w");
      if (stream != null) {
        stream.printf ("%u\n", value);
        stdout.printf ("Successfully wrote %u to %s\n", value, path);
      } else {
        stderr.printf ("Failed to open %s for writing\n", path);
      }
    }
  }
}
