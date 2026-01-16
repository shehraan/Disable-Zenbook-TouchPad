The Asus Zenbook Duo doesn't allow you to disable the touchpad while typing (On KDE) so I decided to create a script that fixes this issue.

Features:
* Disables touchpad when typing with keyboard
* Configurable timeout for touchpad when typing (can be personalized to user speed)
* Disables touchpad when mouse is connected

## Tested On
- **Model**: Asus Zenbook Duo 2024 ux8406ma
- **Distro**: Arch Linux Version 2025.12.01
- **Desktop**: KDE Plasma/Wayland 66.5.4

## Usage

Note: The steps described below work on my current system. If they don't work for you please, create an issue or pull request to address it. 

**STEPS:**
1. Copy disable-touchpad-typing.sh to `/usr/local/bin` (Note that you will have to change the location in the .service file if you decide to put this in a different location)
2. Make it executable by doing the following command:
```
chmod +x /usr/local/bin/touchpad-disable-on-mouse.sh
```
2. Copy *disable-touchpad-while-typing.service* to `/home/$USER/.config/systemd/user/`
3. Enable daemon with the following:
```
systemctl --user enable --now disable-touchpad-while-typing.service
```
4. ENJOY!
