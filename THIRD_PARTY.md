# Sources and licenses

MoonBACnet is an independent MoonBit implementation of a bounded BACnet/IP object/property profile, licensed under Apache-2.0. It is not a line-by-line port of BACpypes3 or an implementation of every part of ASHRAE Standard135. No standard document text, usage databases or third-party fixture corpus is redistributed.

| Source | Use | License / scope |
| --- | --- | --- |
| [BACnet committee](https://bacnet.org/about-bacnet/) and public protocol descriptions | Protocol identity and object/service concepts | Reference only; the standard text is not copied into this repository |
| [BACpypes3](https://github.com/JoelBender/BACpypes3), [0.0.110](https://pypi.org/project/bacpypes3/0.0.110/) | Read APIs and wire behavior; separately installed Python development oracle | Current PyPI `License-Expression` and upstream pyproject declare MIT; a stale classifier says BSD and downloaded sdist does not include a standalone license file. No BACpypes source is copied, translated or bundled in the MoonBit library or Mooncakes archive |
| moonbitlang/async0.22.5 | Native CLI file and stdio host only | Apache-2.0, fetched by official MoonBit tools; no core protocol/runtime binding |
| Local MoonAMQP1/MoonEXR Windows tools | Process-local official compiler path adapters, tools/windows | Apache-2.0; shared engineering support, no application source reused |

The interoperability vectors are constructed by the original `scripts/interop.py` test harness. Example device IDs, vendor999 and measurements are synthetic. They do not claim a real product, vendor assignment or observed deployment.

AI assisted topic comparison, design, source implementation, tests, debugging and documentation. Corrections were validated against typed independent vectors and negative tests. The project maintainer remains responsible for understanding the algorithms, actual deployment behavior, provenance and license compliance. Private application/review materials are excluded from version control and packages.
