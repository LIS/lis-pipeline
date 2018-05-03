# How to configure Jenkins plugins

## Environment minimum requirements
  - Jenkins OS: Ubuntu Xenial 16.04
  - Jenkins version >= 2.89

## Plugins required:
  - nunit
  - junit
  - email-ext
  - simple theme

## Other configuration
  - Enable ssl emails by adding in '/etc/default/jenkins'
  ```bash
      JAVA_ARGS="${JAVA_ARGS} -Dmail.smtp.starttls.enable=true"
  ```