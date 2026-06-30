/*
 * DBeaver - Universal Database Manager
 * Copyright (C) 2010-2026 DBeaver Corp and others
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
package org.jkiss.dbeaver.ui.net.ssh.sshj;

import org.jkiss.code.NotNull;
import org.jkiss.code.Nullable;
import org.jkiss.dbeaver.model.connection.DBPAuthInfo;
import org.jkiss.dbeaver.model.net.ssh.SSHJChallengeResponsePromptProvider;
import org.jkiss.dbeaver.model.net.ssh.config.SSHHostConfiguration;
import org.jkiss.dbeaver.runtime.DBWorkbench;
import org.jkiss.utils.CommonUtils;

/**
 * UI prompt provider for SSHJ keyboard-interactive authentication.
 */
public class SSHJUIPromptProvider implements SSHJChallengeResponsePromptProvider {

    @Nullable
    @Override
    public char[] promptChallengeResponse(
        @NotNull SSHHostConfiguration configuration,
        @Nullable String name,
        @Nullable String instruction,
        @NotNull String prompt,
        boolean echo,
        int attempt
    ) {
        final String title = "SSH verification";
        final StringBuilder description = new StringBuilder();
        description.append(configuration.username()).append('@').append(configuration.hostname()).append(':').append(configuration.port());

        if (CommonUtils.isNotEmpty(name)) {
            description.append("\n").append(name);
        }
        if (CommonUtils.isNotEmpty(instruction)) {
            description.append("\n").append(instruction);
        }
        if (attempt > 1) {
            description.append("\nPrevious response was rejected. Please try again.");
        }

        final DBPAuthInfo authInfo = DBWorkbench.getPlatformUI().promptUserCredentials(
            title,
            description.toString(),
            "",
            "",
            prompt,
            "",
            true,
            false
        );
        if (authInfo == null || authInfo.getUserPassword() == null) {
            return null;
        }
        return authInfo.getUserPassword().toCharArray();
    }
}
