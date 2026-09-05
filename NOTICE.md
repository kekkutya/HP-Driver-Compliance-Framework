# Third-Party Notices

HP Driver Compliance Framework (HP-DCF) includes, derives from, and interoperates with third-party software.

Except where otherwise noted, original HP-DCF source code and documentation are licensed under the MIT License. See `LICENSE`.

## PSAppDeployToolkit

HP-DCF includes PSAppDeployToolkit 4.1.8.

- Project: https://github.com/PSAppDeployToolkit/PSAppDeployToolkit
- Version: 4.1.8
- License: GNU Lesser General Public License v3.0 (LGPL-3.0)
- License copy: `licenses/PSAppDeployToolkit-LGPL-3.0.txt`

Bundled PSAppDeployToolkit distributions are located in the repository under:

- `src/HP-DCF/PSAppDeployToolkit/`
- `src/HP-DCF/SupportFiles/DriverDeployment/PSAppDeployToolkit/`

In release packages, the corresponding locations are:

- `HP-DCF/PSAppDeployToolkit/`
- `HP-DCF/SupportFiles/DriverDeployment/PSAppDeployToolkit/`

The original PSAppDeployToolkit license files are retained with the redistributed components.

The following HP-DCF deployment files are based on PSAppDeployToolkit 4.1.8 templates or configuration files and contain modifications for HP-DCF:

- `src/HP-DCF/Invoke-AppDeployToolkit.ps1`
- `src/HP-DCF/Config/config.psd1`
- `src/HP-DCF/SupportFiles/DriverDeployment/Invoke-AppDeployToolkit.ps1`
- `src/HP-DCF/SupportFiles/DriverDeployment/Config/config.psd1`

PSAppDeployToolkit-derived portions remain subject to the applicable PSAppDeployToolkit license terms.

## PSAppDeployToolkit.WinGet

HP-DCF includes PSAppDeployToolkit.WinGet 1.0.5.

- Project: https://github.com/mjr4077au/PSAppDeployToolkit.WinGet
- Version: 1.0.5
- Copyright: Copyright (c) 2024, Mitch Richters
- License: BSD 3-Clause License
- License copy: `licenses/PSAppDeployToolkit.WinGet-BSD-3-Clause.txt`

The upstream license file is also retained in the repository at:

`src/HP-DCF/PSAppDeployToolkit.WinGet/LICENSE`

and in release packages at:

`HP-DCF/PSAppDeployToolkit.WinGet/LICENSE`

### psyml

PSAppDeployToolkit.WinGet includes psyml 1.0.0, which is therefore redistributed as part of HP-DCF.

- Project: https://github.com/bitrut94/psyml
- Version: 1.0.0
- Copyright: Copyright (c) 2020 Łukasz Burak
- License: MIT License
- License copy: `licenses/psyml-MIT.txt`

### YamlDotNet

The bundled psyml component includes YamlDotNet 9.1.0.

- Project: https://github.com/aaubry/YamlDotNet
- Version: 9.1.0
- Copyright: Copyright (c) 2008-2014 Antoine Aubry and contributors
- License: MIT License
- License copy: `licenses/YamlDotNet-MIT.txt`

## HP Client Management Script Library

HP-DCF uses HP Client Management Script Library (HP CMSL) for HP client-management operations, including HP Image Assistant lifecycle management.

HP CMSL is obtained separately through HP-supported distribution channels and is not redistributed as part of HP-DCF.

HP CMSL is subject to the applicable HP End-User License Agreement:

https://developers.hp.com/license

## HP Image Assistant

HP-DCF uses HP Image Assistant (HPIA) to evaluate and remediate supported HP devices.

HPIA is obtained from HP at runtime using HP-supported tooling and is not redistributed as part of HP-DCF.

HP Image Assistant remains subject to the applicable HP license terms and copyright notices.

## Trademarks and affiliation

HP, HP Image Assistant, and HP Client Management Script Library are trademarks or product names of HP Inc. and/or its affiliates.

Microsoft, Windows, Microsoft Intune, and related product names are trademarks of Microsoft Corporation and/or its affiliates.

PSAppDeployToolkit and other third-party project names remain the property of their respective owners.

HP Driver Compliance Framework is an independent open-source project and is not affiliated with, sponsored by, or endorsed by HP Inc., Microsoft Corporation, PSAppDeployToolkit, or the other third-party projects identified above.
