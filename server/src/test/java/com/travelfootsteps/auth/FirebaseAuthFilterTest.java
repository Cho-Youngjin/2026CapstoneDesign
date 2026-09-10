package com.travelfootsteps.auth;

import com.travelfootsteps.support.StubTokenVerifier;
import jakarta.servlet.FilterChain;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.core.context.SecurityContextHolder;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

class FirebaseAuthFilterTest {

    StubTokenVerifier verifier;
    FirebaseAuthFilter filter;
    FilterChain chain;

    @BeforeEach
    void setUp() {
        verifier = new StubTokenVerifier();
        verifier.register("valid-token", "uid-123");
        filter = new FirebaseAuthFilter(verifier);
        chain = mock(FilterChain.class);
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    @Test
    void valid_bearer_token_sets_uid_as_principal() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/countries");
        request.addHeader("Authorization", "Bearer valid-token");
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(request, response, chain);

        assertThat(SecurityContextHolder.getContext().getAuthentication()).isNotNull();
        assertThat(SecurityContextHolder.getContext().getAuthentication().getName())
                .isEqualTo("uid-123");
        verify(chain).doFilter(request, response);
    }

    @Test
    void invalid_token_leaves_context_empty() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/countries");
        request.addHeader("Authorization", "Bearer garbage");
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(request, response, chain);

        assertThat(SecurityContextHolder.getContext().getAuthentication()).isNull();
        verify(chain).doFilter(request, response);
    }

    @Test
    void missing_header_leaves_context_empty() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/countries");
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(request, response, chain);

        assertThat(SecurityContextHolder.getContext().getAuthentication()).isNull();
        verify(chain).doFilter(request, response);
    }
}
