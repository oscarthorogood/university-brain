---
type: literature-note
authors: "{{authors}}"
year: "{{date | format('YYYY')}}"
citekey: "{{citekey}}"
itemType: "{{itemType}}"
journal: "{{publicationTitle}}"
volume: "{{volume}}"
issue: "{{issue}}"
pages: "{{pages}}"
publisher: "{{publisher}}"
url: "{{url}}"
doi: "{{doi}}"
zotero-link: "{{desktopURI}}"
tags:
  "{ hashTags }":
---

# {{title}}

### Reference Info

* **Bibliography:** {{authorString}} ({{date | format("YYYY")}}). {{title}}. {% if publicationTitle %}{{publicationTitle}}{% endif %}.
* **Online Access:** [DOI Link](https://doi.org/{{doi}}) | [Zotero App]({{desktopURI}})
{% if abstractNote %}
* **Abstract:** {{abstractNote}}
{% endif %}

---

### 🖍️ Extracted Annotations
{% persist "annotations" %}
{% if annotations.length > 0 %}

#### 🟡 Key Quotes & General Points
{% for annotation in annotations | selectattr("color", "equalto", "#ffd43b") -%}
{% if annotation.annotatedText %}* **Quote:** "{{annotation.annotatedText}}" (page {{annotation.pageLabel}}){% endif %}
{% if annotation.imageRelativePath %}* **Image:** ![[{{annotation.imageRelativePath}}]]{% endif %}
{% if annotation.comment %}  * **My Note:** {{annotation.comment}}{% endif %}
{% endfor %}

#### 🟢 Methodologies & Evidence
{% for annotation in annotations | selectattr("color", "equalto", "#529e34") -%}
{% if annotation.annotatedText %}* **Evidence:** "{{annotation.annotatedText}}" (page {{annotation.pageLabel}}){% endif %}
{% if annotation.imageRelativePath %}* **Image:** ![[{{annotation.imageRelativePath}}]]{% endif %}
{% if annotation.comment %}  * **My Note:** {{annotation.comment}}{% endif %}
{% endfor %}

#### 🔴 Core Arguments & Disagreements
{% for annotation in annotations | selectattr("color", "equalto", "#ff5e5e") -%}
{% if annotation.annotatedText %}* **Argument:** "{{annotation.annotatedText}}" (page {{annotation.pageLabel}}){% endif %}
{% if annotation.imageRelativePath %}* **Image:** ![[{{annotation.imageRelativePath}}]]{% endif %}
{% if annotation.comment %}  * **My Note:** {{annotation.comment}}{% endif %}
{% endfor %}

#### 🟣 Other Highlights & Images
{% for annotation in annotations | rejectattr("color", "equalto", "#ffd43b") | rejectattr("color", "equalto", "#529e34") | rejectattr("color", "equalto", "#ff5e5e") -%}
{% if annotation.annotatedText %}* **Highlight:** "{{annotation.annotatedText}}" (page {{annotation.pageLabel}}){% endif %}
{% if annotation.imageRelativePath %}* **Image:** ![[{{annotation.imageRelativePath}}]]{% endif %}
{% if annotation.comment %}  * **My Note:** {{annotation.comment}}{% endif %}
{% endfor %}

{% endif %}
{% endpersist %}