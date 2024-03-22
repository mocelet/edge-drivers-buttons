# SmartThings Edge Driver for modern IKEA buttons

Edge driver for the SmartThings Hub with custom tweaks to support modern Zigbee IKEA smart buttons that were not previously supported by stock or custom drivers.

**Supports**: IKEA RODRET, SOMRIG, modern STYRBAR (firmware 2.4.5) and modern SYMFONISK Gen2 (firmware 1.0.35). Also TRADFRI on/off and TRADFRI 5-button remote.

## Unique features:
- Can expose the release after Held as a Toggled-Up event to use with smart blinds.
- Multi-tap emulation up to 6X to enable double-tap, triple-tap, etc.
- Auto-fire on hold emulation to generate events while Held.
- Fast single-tap mode in SOMRIG to trigger on first-press and avoid the delay created by its native double-tap window.
- Fully functional arrows in STYRBAR. Handles the _messaging feast_ produced by long-pressing arrows and suppresses the ghost On messages. The included 'Any Arrow' component adds a held action that will trigger earlier since the button takes 2 seconds to notify which arrow was held.
- Can suppress Held repetitions in SYMFONISK Gen 2 to avoid repeating the Held action multiple times.

## Notes for End Users

There are two official threads at the SmartThings Community with information and pairing tricks:

- RODRET/SOMRIG/SYMFONISK https://community.smartthings.com/t/edge-ikea-rodret-and-somrig-button-edge-driver/278970

- STYRBAR https://community.smartthings.com/t/edge-ikea-styrbar-button-edge-driver-fw-2-4-5-compatible-full-arrow-support/279296

The driver can be installed in the hub directly from the 'mocelet-shared' driver channel at:

- https://bestow-regional.api.smartthings.com/invite/Kr2zNDg0Wr2A


## Can you add the fingerprint for _this certain button_?

No, the button handlers are not generic, each one is specialized in the particular behaviour of each supported IKEA button. For instance, SOMRIG uses custom clusters and different endpoints and STYRBAR has a complex sequence of events when holding an arrow.

## Notes for Developers

Back when it only offered basic RODRET support, the driver was a debloated stock TRADFRI on/off switch [zigbee-button](https://github.com/SmartThingsCommunity/SmartThingsEdgeDrivers/tree/main/drivers/SmartThings/zigbee-button) driver. I've tried to keep the structure as well as the two init.lua files as unmodified as possible and focus on the new handlers.

All the event handlers for each supported button as well as the custom_features and associated custom_button_utils (multi-tap, auto-fire, etc.) are new original work.

Custom tweaks in particular are device-agnostic and contain helpful comments so they should be easy to reuse in other projects.

## License

The driver is released under the [Apache 2.0 License](LICENSE).