/*
 * DBeaver - Universal Database Manager
 * Copyright (C) 2010-2025 DBeaver Corp and others
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package org.jkiss.dbeaver.model.net.ssh;

import com.jcraft.jsch.Identity;
import net.schmizz.sshj.SSHClient;
import net.schmizz.sshj.common.LoggerFactory;
import net.schmizz.sshj.transport.verification.PromiscuousVerifier;
import net.schmizz.sshj.userauth.method.AuthKeyboardInteractive;
import net.schmizz.sshj.userauth.method.AuthPassword;
import net.schmizz.sshj.userauth.method.AuthMethod;
import net.schmizz.sshj.userauth.method.ChallengeResponseProvider;
import net.schmizz.sshj.userauth.password.PasswordFinder;
import net.schmizz.sshj.userauth.password.PasswordUtils;
import net.schmizz.sshj.userauth.password.Resource;
import org.jkiss.code.NotNull;
import org.jkiss.code.Nullable;
import org.jkiss.dbeaver.DBException;
import org.jkiss.dbeaver.Log;
import org.jkiss.dbeaver.model.net.DBWHandlerConfiguration;
import org.jkiss.dbeaver.model.net.ssh.config.SSHAuthConfiguration;
import org.jkiss.dbeaver.model.net.ssh.config.SSHHostConfiguration;
import org.jkiss.dbeaver.model.runtime.DBRProgressMonitor;
import org.jkiss.dbeaver.runtime.DBWorkbench;
import org.jkiss.dbeaver.utils.GeneralUtils;
import org.jkiss.utils.CommonUtils;
import org.slf4j.Logger;
import org.slf4j.helpers.NOPLogger;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Set;

public class SSHJSessionController extends AbstractSessionController<SSHJSession> {
    private static final Log log = Log.getLog(SSHJSessionController.class);

    @NotNull
    @Override
    protected SSHJSession createSession() {
        return new SSHJSession(this);
    }

    @NotNull
    protected SSHClient createNewSession(
        @NotNull DBRProgressMonitor monitor,
        @NotNull DBWHandlerConfiguration configuration,
        @NotNull SSHHostConfiguration host
    ) throws DBException {
        final int connectTimeout = configuration.getIntProperty(
            SSHConstants.PROP_CONNECT_TIMEOUT,
            SSHConstants.DEFAULT_CONNECT_TIMEOUT);
        final int keepAliveInterval = configuration.getIntProperty(SSHConstants.PROP_ALIVE_INTERVAL) / 1000; // sshj uses seconds for keep-alive interval

        final SSHAuthConfiguration auth = host.auth();
        final SSHClient client = new SSHClient();

        client.setConnectTimeout(connectTimeout);
        client.getConnection().getKeepAlive().setKeepAliveInterval(keepAliveInterval);
        client.getTransport().getConfig().setLoggerFactory(new FilterLoggerFactory());

        try {
            setupHostKeyVerification(client, configuration, host);
        } catch (IOException e) {
            log.debug("Error loading known hosts: " + e.getMessage());
        }

        monitor.subTask(String.format("Instantiate tunnel to %s:%d", host.hostname(), host.port()));

        try {
            client.connect(host.hostname(), host.port());
        } catch (Exception e) {
            throw new DBException("Error establishing SSHJ tunnel", e);
        }

        if (auth instanceof SSHAuthConfiguration.Password password && password.password() != null) {
            try {
                client.auth(host.username(), List.of(
                    new AuthPassword(PasswordUtils.createOneOff(password.password().toCharArray())),
                    new AuthKeyboardInteractive(new DBeaverChallengeResponseProvider(
                        host,
                        password.password(),
                        GeneralUtils.adapt(this, SSHJChallengeResponsePromptProvider.class)
                    ))
                ));
            } catch (Throwable e) {
                throw new DBException("SSH password authentication failed", e);
            }
        } else if (auth instanceof SSHAuthConfiguration.KeyFile key) {
            if (CommonUtils.isEmpty(key.password())) {
                try {
                    client.authPublickey(host.username(), key.path());
                } catch (Throwable e) {
                    throw new DBException("SSH public key authentication failed", e);
                }
            } else {
                try {
                    client.authPublickey(host.username(), client.loadKeys(key.path(), key.password().toCharArray()));
                } catch (Throwable e) {
                    throw new DBException("SSH public key (encrypted) authentication failed", e);
                }
            }
        } else if (auth instanceof SSHAuthConfiguration.KeyData key) {
            final PasswordFinder finder = CommonUtils.isEmpty(key.password())
                ? null
                : PasswordUtils.createOneOff(key.password().toCharArray());
            try {
                client.authPublickey(host.username(), client.loadKeys(key.data(), null, finder));
            } catch (Throwable e) {
                throw new DBException("SSH public key authentication failed", e);
            }
        } else if (auth instanceof SSHAuthConfiguration.Agent) {
            final List<AuthMethod> methods = new ArrayList<>();
            try {
                for (Object identity : createAgentIdentityRepository().getIdentities()) {
                    methods.add(new DBeaverAuthAgent((Identity) identity));
                }
                client.auth(host.username(), methods);
            } catch (Throwable e) {
                throw new DBException("SSH agent authentication failed", e);
            }
        }

        return client;
    }

    private static class DBeaverChallengeResponseProvider implements ChallengeResponseProvider {
        private static final int MAX_RETRIES = 3;

        private final SSHHostConfiguration configuration;
        private final String password;
        private final SSHJChallengeResponsePromptProvider promptProvider;

        private String name;
        private String instruction;
        private int attempts;

        DBeaverChallengeResponseProvider(
            @NotNull SSHHostConfiguration configuration,
            @NotNull String password,
            @Nullable SSHJChallengeResponsePromptProvider promptProvider
        ) {
            this.configuration = configuration;
            this.password = password;
            this.promptProvider = promptProvider;
        }

        @Override
        public List<String> getSubmethods() {
            return Collections.emptyList();
        }

        @Override
        public void init(Resource resource, String name, String instruction) {
            this.name = name;
            this.instruction = instruction;
            attempts++;
        }

        @Override
        public char[] getResponse(String prompt, boolean echo) {
            if (isPasswordPrompt(prompt)) {
                return password.toCharArray();
            }
            if (promptProvider == null) {
                log.debug("No SSHJ keyboard-interactive prompt provider is available for prompt: " + prompt);
                return null;
            }
            return promptProvider.promptChallengeResponse(configuration, name, instruction, prompt, echo, attempts);
        }

        @Override
        public boolean shouldRetry() {
            return attempts < MAX_RETRIES;
        }

        private boolean isPasswordPrompt(@Nullable String prompt) {
            if (prompt == null) {
                return false;
            }
            final String normalized = prompt.toLowerCase();
            return normalized.contains("password") || normalized.contains("passphrase");
        }
    }

    private static void setupHostKeyVerification(
        @NotNull SSHClient client,
        @NotNull DBWHandlerConfiguration configuration,
        @NotNull SSHHostConfiguration actualHostConfiguration
    ) throws IOException {
        if (DBWorkbench.getPlatform().getApplication().isHeadlessMode() ||
            configuration.getBooleanProperty(SSHConstants.PROP_BYPASS_HOST_VERIFICATION)
        ) {
            client.addHostKeyVerifier(new PromiscuousVerifier());
            client.getTransport().getConfig().setVerifyHostKeyCertificates(false);
        } else {
            client.addHostKeyVerifier(new KnownHostsVerifier(SSHUtils.getKnownSshHostsFileOrDefault(), actualHostConfiguration));
        }

        client.loadKnownHosts();
    }

    private static class FilterLoggerFactory implements LoggerFactory {
        private static final Set<String> FILTERED_OUT_CLASSES = Set.of("net.schmizz.sshj.common.StreamCopier");

        @Override
        public Logger getLogger(String s) {
            if (FILTERED_OUT_CLASSES.contains(s)) {
                return NOPLogger.NOP_LOGGER;
            } else {
                return org.slf4j.LoggerFactory.getLogger(s);
            }
        }

        @Override
        public Logger getLogger(Class<?> cls) {
            return getLogger(cls.getName());
        }
    }
}
