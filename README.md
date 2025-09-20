# fakeuser

> [!Warning]
> `fakeuser` is a tool to create fake sub users of a unprivileged user that **PROVIDES NO ISOLATION OR FILE SECURITY**.
> any fakeuser created by `fakeuser` can access **everything of the real user**; and by now, can access everything of other fake users who is created by the same real user.

`fakeuser` is a tool to create fake sub users, that own their own home directory, of a unprivileged user, by setting environment variables.
Each fake user have a unique SSH key pair that is only accessible by the fake user; allowing the fake user to access private git repositories.

`fakeuser` is a shell-only program. Currently, `fakeuser` support Linux and macOS; even fake users created by one OS can be accessed by others.

### Quick start

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/endaytrer/fakeuser/main/fakeuser.sh)"
# follow the instruction to create fake user `admin`
./login
# enter `admin` as the login, and the password you set in the previous step
```

### Todo

- [ ] Password shadow should not be editable by non-admin user
- [ ] Add support for namespace isolation
