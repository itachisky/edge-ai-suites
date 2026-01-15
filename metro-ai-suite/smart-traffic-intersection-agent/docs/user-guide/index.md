# Smart Traffic Intersection Agent Overview

<!--hide_directive
<div class="component_card_widget">
  <a class="icon_github" href="https://github.com/open-edge-platform/edge-ai-suites/tree/main/metro-ai-suite/smart-traffic-intersection-agent">
     GitHub project
  </a>
  <a class="icon_document" href="https://github.com/open-edge-platform/edge-ai-suites/blob/main/metro-ai-suite/smart-traffic-intersection-agent/README.md">
     Readme
  </a>
</div>
hide_directive-->

This application uses AI agent to handle a given traffic intersection by analyzing various traffic scenarios at the intersection. It provides driving suggestions, sends alerts and provides interface for other agents to plug-in and get the required information about a particular traffic intersection. Proposed deployments to happen at edge at each traffic intersection only.


## Overview

The microservice processes real-time traffic data from MQTT streams and provides advanced analytics including directional traffic density monitoring, VLM-powered traffic scene analysis, and comprehensive traffic summaries. It supports sliding window analysis, sustained traffic detection, and intelligent camera image management for enhanced traffic insights.

## How it Works

## Learn More

- [System Requirements](./system-requirements.md): Check the hardware and software requirements for deploying the application.
- [Get Started](./get-started.md): Follow step-by-step instructions to set up the application.
- [How to build from source](./how-to-build-from-source.md): How to build and deploy the application using Docker Compose.

<!--hide_directive
:::{toctree}
:hidden:

system-requirements
get-started
how-to-build-from-source
api-reference
release-notes


:::
hide_directive-->

.. toctree::
   :hidden:
   
   Overview

.. toctree::
   
   system-requirements
   get-started

.. toctree::
   :caption: How to

   how-to-build-from-source
   
.. toctree::
   :caption: References
   
   environment-variables
   api-reference
   
.. toctree::
   
   release-notes
