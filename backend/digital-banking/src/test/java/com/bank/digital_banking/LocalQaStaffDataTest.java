package com.bank.digital_banking;

import com.bank.digital_banking.config.LocalQaStaffData;
import com.bank.digital_banking.module.auth.entity.ERole;
import com.bank.digital_banking.module.auth.entity.Role;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.auth.repository.RoleRepository;
import com.bank.digital_banking.module.auth.repository.UserRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Optional;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class LocalQaStaffDataTest {
    UserRepository users;
    RoleRepository roles;
    PasswordEncoder encoder;
    LocalQaStaffData fixture;
    Role employee;
    @BeforeEach void setup() {
        users = mock(UserRepository.class); roles = mock(RoleRepository.class);
        encoder = mock(PasswordEncoder.class);
        fixture = new LocalQaStaffData(users, roles, encoder);
        ReflectionTestUtils.setField(fixture, "username", "qa.staff");
        ReflectionTestUtils.setField(fixture, "email", "qa.staff@example.test");
        ReflectionTestUtils.setField(fixture, "password", "TestFixtureOnly!");
        employee = Role.builder().id(1L).name(ERole.ROLE_BANK_EMPLOYEE).build();
    }
    @Test void createsOnlySeparateStaffWithEncodedPassword() {
        when(roles.findByName(ERole.ROLE_BANK_EMPLOYEE)).thenReturn(Optional.of(employee));
        when(encoder.encode(anyString())).thenReturn("encoded");
        fixture.run(null);
        verify(users).save(argThat(u -> u.getUsername().equals("qa.staff")
                && u.getEmail().equals("qa.staff@example.test") && u.getPassword().equals("encoded")
                && u.getRoles().equals(Set.of(employee))));
    }
    @Test void existingCustomerIsNeverPromotedOrModified() {
        when(users.findByUsername("qa.staff")).thenReturn(Optional.of(User.builder()
                .username("qa.staff").email("qa.staff@example.test").roles(Set.of()).build()));
        assertThrows(IllegalStateException.class, () -> fixture.run(null));
        verify(users, never()).save(any());
    }
    @Test void emailCollisionDoesNotChangeExistingUser() {
        when(users.findByEmail("qa.staff@example.test")).thenReturn(Optional.of(User.builder().build()));
        assertThrows(IllegalStateException.class, () -> fixture.run(null));
        verify(users, never()).save(any());
    }
    @Test void existingMatchingStaffIsPreserved() {
        when(users.findByUsername("qa.staff")).thenReturn(Optional.of(User.builder()
                .username("qa.staff").email("qa.staff@example.test").password("encoded")
                .roles(Set.of(employee)).build()));
        when(encoder.matches("TestFixtureOnly!", "encoded")).thenReturn(true);
        fixture.run(null);
        verify(users, never()).save(any());
    }
    @Test void invalidConfigurationFailsBeforeDatabaseWrites() {
        ReflectionTestUtils.setField(fixture, "password", "replace_me");
        assertThrows(IllegalArgumentException.class, () -> fixture.run(null));
        verifyNoInteractions(users);
    }
}
