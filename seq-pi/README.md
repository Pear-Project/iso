# Raspberry Pi image: boot test

<!-- boot-seq:begin -->

Result: **FAIL TEST ❌**  

**Success score: 85/100**

| Test | Score |
|---|---|
| Boot | 100/100 |
| UI sanity | 50/100 |
| Installable | 100/100 |
| Usability | 90/100 |

Usability checks:

| Check | Result |
|---|---|
| login + desktop | ✅  |
| UI sanity (installed) | ❌ top 88% / dock 100% |
| Konsole opens | ✅  |
| os-release says pearOS | ✅  |
| sudo apt-get dist-upgrade | ✅  |
| Pafari opens | ✅  |
| Calculator opens | ✅  |
| Notes opens | ✅  |
| Finder opens | ✅  |
| Kate opens | ✅  |


> **Why it failed:** The installed desktop looks different from the reference: menu bar 88.4%, dock 100.0% (each must be at least 90%).

This ISO was **not published**; it was saved as a quarantined `FAIL_TEST` build.

One screenshot every 10s.

1. `10s` — ![boot 1](web/1.webp)
2. `20s` — ![boot 2](web/2.webp)
3. `30s` — ![boot 3](web/3.webp)
4. `40s` — ![boot 4](web/4.webp)
5. `50s` — ![boot 5](web/5.webp)
6. `60s` — ![boot 6](web/6.webp)
7. `70s` — ![boot 7](web/7.webp)
8. `80s` — ![boot 8](web/8.webp)
9. `90s` — ![boot 9](web/9.webp)
10. `100s` — desktop ready, then clicked **Install pearOS** in Welcome — ![boot 10](web/10.webp)
11. `110s` — pearOS installer loading — ![boot 11](web/11.webp)
12. `120s` — pearOS installer loading — ![boot 12](web/12.webp)
13. `130s` — Language screen, then selected English — ![boot 13](web/13.webp)
14. `140s` — Language screen, then clicked Next — ![boot 14](web/14.webp)
15. `150s` — Recovery screen, then selected **Install pearOS Goldwing** — ![boot 15](web/15.webp)
16. `160s` — Recovery screen, then clicked **Continue** — ![boot 16](web/16.webp)
17. `170s` — Installer welcome, then clicked **Continue** — ![boot 17](web/17.webp)
18. `180s` — Terms and Conditions, then clicked **Continue** — ![boot 18](web/18.webp)
19. `190s` — ![boot 19](web/19.webp)
20. `200s` — ![boot 20](web/20.webp)
21. `210s` — ![boot 21](web/21.webp)
22. `220s` — ![boot 22](web/22.webp)
23. `230s` — ![boot 23](web/23.webp)
24. `240s` — ![boot 24](web/24.webp)
25. `250s` — ![boot 25](web/25.webp)
26. `260s` — Calamares — ![boot 26](web/26.webp)
27. `270s` — Calamares: Welcome, clicked Next — ![boot 27](web/27.webp)
28. `280s` — Calamares: Location, clicked Next — ![boot 28](web/28.webp)
29. `290s` — Calamares: Keyboard, clicked Next — ![boot 29](web/29.webp)
30. `300s` — Calamares: Partitions, selected Erase disk — ![boot 30](web/30.webp)
31. `310s` — Calamares: Partitions, clicked Next — ![boot 31](web/31.webp)
32. `320s` — Calamares: Summary, clicked Install — ![boot 32](web/32.webp)
33. `330s` — Calamares: installing (2 min) — ![boot 33](web/33.webp)
34. `340s` — Calamares: installation finished — ![boot 34](web/34.webp)
35. `350s` — Installed system: first boot — ![boot 35](web/35.webp)
36. `360s` — Installed system: first boot — ![boot 36](web/36.webp)
37. `370s` — Installed system: first boot — ![boot 37](web/37.webp)
38. `380s` — Installed system: first boot — ![boot 38](web/38.webp)
39. `390s` — Installed system: first boot — ![boot 39](web/39.webp)
40. `400s` — Installed system: reached the login screen / desktop — ![boot 40](web/40.webp)
41. `410s` — First boot: country — ![boot 41](web/41.webp)
42. `420s` — First boot: transfer — ![boot 42](web/42.webp)
43. `430s` — First boot: languages — ![boot 43](web/43.webp)
44. `440s` — First boot: accessibility — ![boot 44](web/44.webp)
45. `450s` — First boot: data & privacy — ![boot 45](web/45.webp)
46. `460s` — First boot: PearID — ![boot 46](web/46.webp)
47. `470s` — First boot: create account — ![boot 47](web/47.webp)
48. `480s` — First boot: account filled in — ![boot 48](web/48.webp)
49. `490s` — First boot: terms — ![boot 49](web/49.webp)
50. `500s` — First boot: location services — ![boot 50](web/50.webp)
51. `510s` — First boot: time zone — ![boot 51](web/51.webp)
52. `520s` — First boot: analytics — ![boot 52](web/52.webp)
53. `530s` — First boot: screen time — ![boot 53](web/53.webp)
54. `540s` — First boot: Piri — ![boot 54](web/54.webp)
55. `550s` — First boot: look — ![boot 55](web/55.webp)
56. `560s` — First boot: updates — ![boot 56](web/56.webp)
57. `570s` — First boot: ready — ![boot 57](web/57.webp)
58. `580s` — First boot: applying settings — ![boot 58](web/58.webp)
59. `590s` — Login screen — ![boot 59](web/59.webp)
60. `600s` — Login screen — ![boot 60](web/60.webp)
61. `610s` — Login screen — ![boot 61](web/61.webp)
62. `620s` — Login screen — ![boot 62](web/62.webp)
63. `630s` — Login screen — ![boot 63](web/63.webp)
64. `640s` — Login screen — ![boot 64](web/64.webp)
65. `650s` — Login screen — ![boot 65](web/65.webp)
66. `660s` — Login screen — ![boot 66](web/66.webp)
67. `670s` — Login screen — ![boot 67](web/67.webp)
68. `680s` — Login screen — ![boot 68](web/68.webp)
69. `690s` — Login screen — ![boot 69](web/69.webp)
70. `700s` — Login screen — ![boot 70](web/70.webp)
71. `710s` — Logging in — ![boot 71](web/71.webp)
72. `720s` — Logging in — ![boot 72](web/72.webp)
73. `730s` — Logging in — ![boot 73](web/73.webp)
74. `740s` — Logging in — ![boot 74](web/74.webp)
75. `750s` — Logging in — ![boot 75](web/75.webp)
76. `760s` — Logging in — ![boot 76](web/76.webp)
77. `770s` — Installed system: desktop — ![boot 77](web/77.webp)
78. `780s` — Konsole opened — ![boot 78](web/78.webp)
79. `790s` — Konsole: cat /etc/os-release — ![boot 79](web/79.webp)
80. `800s` — Konsole: apt-get dist-upgrade succeeded — ![boot 80](web/80.webp)
81. `810s` — App: Pafari opened — ![boot 81](web/81.webp)
82. `820s` — App: Calculator opened — ![boot 82](web/82.webp)
83. `830s` — App: Notes opened — ![boot 83](web/83.webp)
84. `840s` — App: Finder opened — ![boot 84](web/84.webp)
85. `850s` — App: Kate opened — ![boot 85](web/85.webp)

<!-- boot-seq:end -->
<!-- ui-sanity:begin -->

Result: **menu bar + dock look as expected ✅**  
Compared against the reference `tests/ui-reference/debian/desktop.png` (% of pixels within ±16 per channel; pass ≥ 90%).

| Area | Similarity |
|---|---|
| Top bar (first 30 px) | 94.7% |
| Dock (last 100 px) | 100.0% |

Current frame: ![desktop](web/10.webp)

<!-- ui-sanity:end -->
