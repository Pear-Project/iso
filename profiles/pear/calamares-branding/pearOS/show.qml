/* === This file is part of Calamares - <https://calamares.io> ===
 *
 *   SPDX-FileCopyrightText: 2015 Teo Mrnjavac <teo@kde.org>
 *   SPDX-FileCopyrightText: 2018 Adriaan de Groot <groot@kde.org>
 *   SPDX-License-Identifier: GPL-3.0-or-later
 *
 *   Calamares is Free Software: see the License-Identifier above.
 *
 */

import QtQuick 2.15;
import calamares.slideshow 1.0;

Presentation
{
    id: presentation

    // Single static slide; no auto-advance needed.

    Slide {
        anchors.fill: parent
        anchors.verticalCenterOffset: 0

        Image {
            id: background1
            source: "slide1.png"
            width: parent.width; height: parent.height
            horizontalAlignment: Image.AlignCenter
            verticalAlignment: Image.AlignTop
            fillMode: Image.Stretch
            anchors.fill: parent
        }
    }

    // When this slideshow is loaded as a V1 slideshow, only
    // activatedInCalamares is set, which starts the timer (see above).
    //
    // In V2, also the onActivate() and onLeave() methods are called.
    // These example functions log a message (and re-start the slides
    // from the first).
    function onActivate() {
        //console.log("QML Component (default slideshow) activated");
        presentation.currentSlide = 0;
    }

    //function onLeave() {
        //console.log("QML Component (default slideshow) deactivated");
   // }
}
